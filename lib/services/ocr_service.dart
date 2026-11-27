import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/scan_entry.dart';

class OcrScanResult {
  final String rawText;
  final String filteredText;
  final String? evidenceImagePath;
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

  InputImage? _buildInputImage(CameraImage image, int sensorOrientation) {
    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation90deg;

    // Fast path: Android NV21 single plane
    if (image.format.group == ImageFormatGroup.nv21 &&
        image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Fallback: YUV_420_888 (3 planes) converted to NV21 buffer
    if (image.planes.length == 3) {
      final nv21 = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height) ~/ 2);
    int outIdx = 0;

    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    for (int row = 0; row < height; row++) {
      final rowStart = row * yRowStride;
      for (int col = 0; col < width; col++) {
        nv21[outIdx++] = yBytes[rowStart + col * yPixelStride];
      }
    }

    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final halfH = height ~/ 2;
    final halfW = width ~/ 2;

    for (int row = 0; row < halfH; row++) {
      final rowStart = row * uvRowStride;
      for (int col = 0; col < halfW; col++) {
        final offset = rowStart + col * uvPixelStride;
        nv21[outIdx++] = vBytes[offset];
        nv21[outIdx++] = uBytes[offset];
      }
    }

    return nv21;
  }

  /// Real-time QR/Barcode scan directly from live CameraImage stream.
  Future<OcrScanResult?> processBarcodeStream({
    required CameraImage image,
    required int sensorOrientation,
  }) async {
    final inputImage = _buildInputImage(image, sensorOrientation);
    if (inputImage == null) return null;

    final barcodes = await _barcodeScanner.processImage(inputImage);
    if (barcodes.isEmpty) return null;

    for (final b in barcodes) {
      final val = (b.rawValue ?? b.displayValue ?? '').trim();
      if (val.isEmpty) continue;
      final isQr = b.format == BarcodeFormat.qrCode;
      return OcrScanResult(
        rawText: val,
        filteredText: val,
        evidenceImagePath: null,
        scanType: isQr ? 'qr' : 'barcode',
        barcodeFormat: b.format.name.toUpperCase(),
      );
    }
    return null;
  }

  /// Real-time OCR directly from live CameraImage stream, filtering TextLines
  /// whose boundingBox center lies inside [roiNormalized] (0..1).
  Future<OcrScanResult?> processOcrStream({
    required CameraImage image,
    required int sensorOrientation,
    required Rect roiNormalized,
    required OcrFilterMode filterMode,
  }) async {
    final inputImage = _buildInputImage(image, sensorOrientation);
    if (inputImage == null) return null;

    final recognized = await _recognizer.processImage(inputImage);
    if (recognized.blocks.isEmpty) return null;

    final isRotated = sensorOrientation == 90 || sensorOrientation == 270;
    final imgW = (isRotated ? image.height : image.width).toDouble();
    final imgH = (isRotated ? image.width : image.height).toDouble();
    if (imgW <= 0 || imgH <= 0) return null;

    final forgivingRoi = roiNormalized.inflate(0.03);
    final matchedLines = <TextLine>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        final cx = box.center.dx / imgW;
        final cy = box.center.dy / imgH;
        if (forgivingRoi.contains(Offset(cx, cy))) {
          matchedLines.add(line);
        }
      }
    }

    if (matchedLines.isEmpty) return null;

    matchedLines.sort(
      (a, b) => a.boundingBox.top.compareTo(b.boundingBox.top),
    );
    final raw = matchedLines.map((l) => l.text.trim()).join(' ').trim();
    final filtered = applyOcrFilter(raw, filterMode);
    if (filtered.isEmpty) return null;

    return OcrScanResult(
      rawText: raw,
      filteredText: filtered,
      evidenceImagePath: null,
      scanType: 'ocr',
    );
  }

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

  /// Scans QR Code and 1D/2D Barcodes offline from a photo file (manual/gallery).
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
