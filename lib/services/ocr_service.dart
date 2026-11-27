import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/scan_entry.dart';

class OcrScanResult {
  final String rawText;
  final String filteredText;
  final String evidenceImagePath;
  final String scanType; // 'ocr', 'qr', 'barcode'
  final String? barcodeFormat;

  const OcrScanResult({
    required this.rawText,
    required this.filteredText,
    required this.evidenceImagePath,
    this.scanType = 'ocr',
    this.barcodeFormat,
  });
}

class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.all]);

  Future<String> _prepareEvidenceCrop({
    required String sourceImagePath,
    Rect? roiNormalized,
  }) async {
    final bytes = await File(sourceImagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);

    final docsDir = await getApplicationDocumentsDirectory();
    final evidenceDir = Directory('${docsDir.path}/evidence');
    if (!await evidenceDir.exists()) {
      await evidenceDir.create(recursive: true);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final evidencePath = '${evidenceDir.path}/scan_$stamp.jpg';

    if (decoded != null) {
      final oriented = img.bakeOrientation(decoded);
      img.Image cropped = oriented;
      if (roiNormalized != null) {
        final cropX = (roiNormalized.left * oriented.width)
            .round()
            .clamp(0, oriented.width - 1);
        final cropY = (roiNormalized.top * oriented.height)
            .round()
            .clamp(0, oriented.height - 1);
        final cropW = (roiNormalized.width * oriented.width)
            .round()
            .clamp(16, oriented.width - cropX);
        final cropH = (roiNormalized.height * oriented.height)
            .round()
            .clamp(16, oriented.height - cropY);

        cropped = img.copyCrop(
          oriented,
          x: cropX,
          y: cropY,
          width: cropW,
          height: cropH,
        );
      }

      await File(evidencePath).writeAsBytes(
        img.encodeJpg(cropped, quality: 88),
        flush: true,
      );
    } else {
      await File(sourceImagePath).copy(evidencePath);
    }

    return evidencePath;
  }

  /// Crops [sourceImagePath] using normalized [roiNormalized] (0..1 coords),
  /// saves the clean cropped photo as permanent evidence, optionally enhances
  /// contrast on a temporary copy, and runs offline ML Kit OCR.
  Future<OcrScanResult> processImage({
    required String sourceImagePath,
    required OcrFilterMode filterMode,
    Rect? roiNormalized,
    bool enhanceContrast = true,
  }) async {
    final evidencePath = await _prepareEvidenceCrop(
      sourceImagePath: sourceImagePath,
      roiNormalized: roiNormalized,
    );

    String ocrTargetPath = evidencePath;
    File? tempPreprocessed;

    if (enhanceContrast) {
      final bytes = await File(evidencePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final enhanced = img.adjustColor(
          img.grayscale(decoded),
          contrast: 1.45,
          brightness: 1.05,
        );
        final tempDir = await getTemporaryDirectory();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        tempPreprocessed = File('${tempDir.path}/ocr_pre_$stamp.jpg');
        await tempPreprocessed.writeAsBytes(
          img.encodeJpg(enhanced, quality: 92),
          flush: true,
        );
        ocrTargetPath = tempPreprocessed.path;
      }
    }

    try {
      final inputImage = InputImage.fromFilePath(ocrTargetPath);
      final recognized = await _recognizer.processImage(inputImage);
      final raw = recognized.text.trim();
      final filtered = applyOcrFilter(raw, filterMode);

      return OcrScanResult(
        rawText: raw,
        filteredText: filtered,
        evidenceImagePath: evidencePath,
        scanType: 'ocr',
      );
    } finally {
      if (tempPreprocessed != null && await tempPreprocessed.exists()) {
        try {
          await tempPreprocessed.delete();
        } catch (_) {}
      }
    }
  }

  /// Scans QR Code and 1D/2D Barcodes offline using Google ML Kit.
  /// Tries the ROI crop first, then falls back to full image if barcode is slightly clipped.
  Future<OcrScanResult> processBarcode({
    required String sourceImagePath,
    Rect? roiNormalized,
  }) async {
    final evidencePath = await _prepareEvidenceCrop(
      sourceImagePath: sourceImagePath,
      roiNormalized: roiNormalized,
    );

    List<Barcode> barcodes = await _barcodeScanner.processImage(
      InputImage.fromFilePath(evidencePath),
    );

    if (barcodes.isEmpty && roiNormalized != null) {
      barcodes = await _barcodeScanner.processImage(
        InputImage.fromFilePath(sourceImagePath),
      );
    }

    if (barcodes.isEmpty) {
      return OcrScanResult(
        rawText: '',
        filteredText: '',
        evidenceImagePath: evidencePath,
        scanType: 'barcode',
        barcodeFormat: 'NOT_FOUND',
      );
    }

    final first = barcodes.first;
    final val = (first.rawValue ?? first.displayValue ?? '').trim();
    final isQr = first.format == BarcodeFormat.qrCode;
    final fmtName = first.format.name.toUpperCase();

    return OcrScanResult(
      rawText: val,
      filteredText: val,
      evidenceImagePath: evidencePath,
      scanType: isQr ? 'qr' : 'barcode',
      barcodeFormat: fmtName,
    );
  }

  Future<void> dispose() async {
    await _recognizer.close();
    await _barcodeScanner.close();
  }
}
