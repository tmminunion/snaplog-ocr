import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/scan_entry.dart';

class OcrScanResult {
  final String rawText;
  final String filteredText;
  final String evidenceImagePath;

  const OcrScanResult({
    required this.rawText,
    required this.filteredText,
    required this.evidenceImagePath,
  });
}

class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Crops [sourceImagePath] using normalized [roiNormalized] (0..1 coords),
  /// saves the clean cropped photo as permanent evidence, optionally enhances
  /// contrast on a temporary copy, and runs offline ML Kit OCR.
  Future<OcrScanResult> processImage({
    required String sourceImagePath,
    required OcrFilterMode filterMode,
    Rect? roiNormalized,
    bool enhanceContrast = true,
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

    String ocrTargetPath = evidencePath;
    File? tempPreprocessed;

    if (decoded != null) {
      // Fix Android camera EXIF rotation so ROI coordinates match screen preview
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

      // Save clean color ROI crop as permanent photo evidence
      await File(evidencePath).writeAsBytes(
        img.encodeJpg(cropped, quality: 88),
        flush: true,
      );

      // Optional contrast boost on temp image for better OCR on dark/chalk/meter surfaces
      if (enhanceContrast) {
        final enhanced = img.adjustColor(
          img.grayscale(cropped.clone()),
          contrast: 1.45,
          brightness: 1.05,
        );
        final tempDir = await getTemporaryDirectory();
        tempPreprocessed = File('${tempDir.path}/ocr_pre_$stamp.jpg');
        await tempPreprocessed.writeAsBytes(
          img.encodeJpg(enhanced, quality: 92),
          flush: true,
        );
        ocrTargetPath = tempPreprocessed.path;
      }
    } else {
      await File(sourceImagePath).copy(evidencePath);
      ocrTargetPath = evidencePath;
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
      );
    } finally {
      if (tempPreprocessed != null && await tempPreprocessed.exists()) {
        try {
          await tempPreprocessed.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }
}
