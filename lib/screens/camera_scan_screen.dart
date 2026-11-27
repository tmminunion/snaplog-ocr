import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan_entry.dart';
import '../services/ocr_service.dart';
import '../widgets/roi_overlay_painter.dart';

class CameraScanScreen extends StatefulWidget {
  final ScannerMode initialMode;

  const CameraScanScreen({
    super.key,
    this.initialMode = ScannerMode.ocr,
  });

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with SingleTickerProviderStateMixin {
  final OcrService _ocrService = OcrService();
  final ImagePicker _picker = ImagePicker();

  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  bool _isProcessing = false;
  bool _flashOn = false;
  bool _enhanceContrast = true;
  bool _wideStripRoi = true;
  late ScannerMode _scannerMode;
  OcrFilterMode _filterMode = OcrFilterMode.all;

  late final AnimationController _laserAnim;

  @override
  void initState() {
    super.initState();
    _scannerMode = widget.initialMode;
    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'Kamera tidak ditemukan di perangkat.');
        }
        return;
      }
      final backCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Gagal membuka kamera: $e');
      }
    }
  }

  @override
  void dispose() {
    _laserAnim.dispose();
    _cameraController?.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  Rect _computeRoiRect(Size size) {
    if (_scannerMode == ScannerMode.qrBarcode) {
      final boxSize = size.width * 0.72;
      final left = (size.width - boxSize) / 2;
      final top = (size.height - boxSize) * 0.38;
      return Rect.fromLTWH(left, top, boxSize, boxSize);
    }
    final width = size.width * 0.86;
    final height = _wideStripRoi ? size.height * 0.16 : size.height * 0.30;
    final left = (size.width - width) / 2;
    final top = (size.height - height) * 0.42;
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _computeNormalizedRoi(Size size) {
    final rect = _computeRoiRect(size);
    return Rect.fromLTWH(
      (rect.left / size.width).clamp(0.0, 1.0),
      (rect.top / size.height).clamp(0.0, 1.0),
      (rect.width / size.width).clamp(0.1, 1.0),
      (rect.height / size.height).clamp(0.1, 1.0),
    );
  }

  Future<void> _toggleFlash() async {
    final ctrl = _cameraController;
    if (ctrl == null || !_cameraReady) return;
    try {
      final next = !_flashOn;
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } catch (_) {}
  }

  Future<void> _captureAndScan(Size viewportSize) async {
    if (_isProcessing) return;
    final ctrl = _cameraController;
    if (ctrl == null || !_cameraReady) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final shot = await ctrl.takePicture();
      final roiNorm = _computeNormalizedRoi(viewportSize);

      final OcrScanResult result;
      if (_scannerMode == ScannerMode.qrBarcode) {
        result = await _ocrService.processBarcode(
          sourceImagePath: shot.path,
          roiNormalized: roiNorm,
        );
      } else {
        result = await _ocrService.processImage(
          sourceImagePath: shot.path,
          filterMode: _filterMode,
          roiNormalized: roiNorm,
          enhanceContrast: _enhanceContrast,
        );
      }

      if (mounted) {
        await _showConfirmSheet(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses scan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _isProcessing = true);
      final OcrScanResult result;
      if (_scannerMode == ScannerMode.qrBarcode) {
        result = await _ocrService.processBarcode(
          sourceImagePath: picked.path,
          roiNormalized: null,
        );
      } else {
        result = await _ocrService.processImage(
          sourceImagePath: picked.path,
          filterMode: _filterMode,
          roiNormalized: null,
          enhanceContrast: _enhanceContrast,
        );
      }

      if (mounted) {
        await _showConfirmSheet(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membaca gambar galeri: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showConfirmSheet(OcrScanResult result) async {
    final textCtrl = TextEditingController(
      text: result.filteredText.isNotEmpty
          ? result.filteredText
          : result.rawText,
    );
    final noteCtrl = TextEditingController();
    final isCodeScan = result.scanType == 'qr' || result.scanType == 'barcode';

    final badgeText = isCodeScan
        ? (result.barcodeFormat ?? result.scanType.toUpperCase())
        : _filterMode.shortLabel.toUpperCase();

    final savedEntry = await showModalBottomSheet<ScanEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11182C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      isCodeScan
                          ? Icons.qr_code_scanner_rounded
                          : Icons.document_scanner_rounded,
                      color: const Color(0xFF00E5FF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCodeScan ? 'HASIL QR / BARCODE' : 'HASIL SCAN OCR',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    color: const Color(0xFF050914),
                    child: Image.file(
                      File(result.evidenceImagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: textCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: isCodeScan
                        ? 'Isi QR / Barcode'
                        : 'Hasil Teks / Angka',
                    hintText: isCodeScan && textCtrl.text.isEmpty
                        ? 'QR/Barcode tidak terdeteksi — coba dekatkan kamera'
                        : null,
                    hintStyle: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 12.5,
                    ),
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF0A0F1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00E5FF),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Catatan (opsional)',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF0A0F1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          try {
                            File(result.evidenceImagePath).deleteSync();
                          } catch (_) {}
                          Navigator.of(ctx).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          side: const BorderSide(color: Color(0xFF334155)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Ulang'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          final finalVal = textCtrl.text.trim();
                          if (finalVal.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Hasil scan tidak boleh kosong.'),
                              ),
                            );
                            return;
                          }
                          final entry = ScanEntry(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            text: finalVal,
                            rawText: result.rawText,
                            note: noteCtrl.text.trim(),
                            filterMode: isCodeScan
                                ? 'barcode'
                                : _filterMode.name,
                            scanType: result.scanType,
                            barcodeFormat: result.barcodeFormat,
                            imagePath: result.evidenceImagePath,
                            createdAt: DateTime.now(),
                          );
                          Navigator.of(ctx).pop(entry);
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          'Simpan',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: const Color(0xFF0A0F1E),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (savedEntry != null && mounted) {
      Navigator.of(context).pop(savedEntry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isQrMode = _scannerMode == ScannerMode.qrBarcode;

    return Scaffold(
      backgroundColor: const Color(0xFF050914),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final roiRect = _computeRoiRect(viewportSize);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_cameraReady && _cameraController != null)
                CameraPreview(_cameraController!)
              else if (_cameraError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.no_photography_rounded,
                          color: Color(0xFFFF5252),
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _cameraError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('Pilih Foto dari Galeri'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                ),

              if (_cameraReady)
                AnimatedBuilder(
                  animation: _laserAnim,
                  builder: (_, __) => CustomPaint(
                    painter: RoiOverlayPainter(
                      roiRect: roiRect,
                      scanProgress: _laserAnim.value,
                      isProcessing: _isProcessing,
                    ),
                    size: viewportSize,
                  ),
                ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _circleBtn(
                              icon: Icons.arrow_back_rounded,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                            if (!isQrMode) ...[
                              _circleBtn(
                                icon: _wideStripRoi
                                    ? Icons.crop_16_9_rounded
                                    : Icons.crop_square_rounded,
                                active: !_wideStripRoi,
                                tooltip: 'Ubah ukuran kotak ROI',
                                onTap: () => setState(
                                  () => _wideStripRoi = !_wideStripRoi,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _circleBtn(
                                icon: Icons.contrast_rounded,
                                active: _enhanceContrast,
                                tooltip: 'Boost Kontras OCR',
                                onTap: () => setState(
                                  () => _enhanceContrast = !_enhanceContrast,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _circleBtn(
                              icon: _flashOn
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              active: _flashOn,
                              tooltip: 'Flash',
                              onTap: _toggleFlash,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0F1E).withAlpha(215),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFF334155),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _modeTab(
                                label: 'OCR TEKS',
                                icon: Icons.document_scanner_rounded,
                                selected: !isQrMode,
                                onTap: () => setState(
                                  () => _scannerMode = ScannerMode.ocr,
                                ),
                              ),
                              _modeTab(
                                label: 'QR / BARCODE',
                                icon: Icons.qr_code_scanner_rounded,
                                selected: isQrMode,
                                onTap: () => setState(
                                  () => _scannerMode = ScannerMode.qrBarcode,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_cameraReady)
                Positioned(
                  top: roiRect.top - 34,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0F1E).withAlpha(190),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withAlpha(110),
                        ),
                      ),
                      child: Text(
                        isQrMode
                            ? 'Arahkan QR Code / Barcode ke dalam kotak'
                            : (_enhanceContrast
                                ? 'ROI Aktif • Kontras Tinggi ON'
                                : 'ROI Aktif • Mode Standar'),
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF050914).withAlpha(235),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isQrMode)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: OcrFilterMode.values.map((mode) {
                              final selected = mode == _filterMode;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _filterMode = mode),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFF00E5FF)
                                          : const Color(0xFF131C33),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFF00E5FF)
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                    child: Text(
                                      mode.label,
                                      style: TextStyle(
                                        color: selected
                                            ? const Color(0xFF050914)
                                            : const Color(0xFFCBD5E1),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          )
                        else
                          const Text(
                            'QR • Code128 • Code39 • EAN-13 • UPC • DataMatrix',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 18),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _circleBtn(
                              icon: Icons.photo_library_rounded,
                              size: 48,
                              tooltip: 'Scan dari Galeri',
                              onTap: _pickFromGallery,
                            ),
                            GestureDetector(
                              onTap: _isProcessing
                                  ? null
                                  : () => _captureAndScan(viewportSize),
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isQrMode
                                        ? const Color(0xFF00E676)
                                        : const Color(0xFF00E5FF),
                                    width: 3.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isQrMode
                                              ? const Color(0xFF00E676)
                                              : const Color(0xFF00E5FF))
                                          .withAlpha(90),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(5),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isProcessing
                                        ? const Color(0xFFFFB300)
                                        : (isQrMode
                                            ? const Color(0xFF00E676)
                                            : const Color(0xFF00E5FF)),
                                  ),
                                  child: _isProcessing
                                      ? const Padding(
                                          padding: EdgeInsets.all(18),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: Color(0xFF050914),
                                          ),
                                        )
                                      : Icon(
                                          isQrMode
                                              ? Icons.qr_code_scanner_rounded
                                              : Icons.document_scanner_rounded,
                                          color: const Color(0xFF050914),
                                          size: 30,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00E5FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? const Color(0xFF050914) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF050914)
                    : const Color(0xFFCBD5E1),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    double size = 40,
    String? tooltip,
  }) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? const Color(0xFF00E5FF).withAlpha(45)
              : const Color(0xFF0A0F1E).withAlpha(180),
          border: Border.all(
            color: active ? const Color(0xFF00E5FF) : const Color(0xFF334155),
          ),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFF00E5FF) : Colors.white,
          size: size * 0.5,
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }
}
