import 'package:flutter/material.dart';

class RoiOverlayPainter extends CustomPainter {
  final Rect roiRect;
  final double scanProgress; // 0.0 .. 1.0
  final bool isProcessing;

  RoiOverlayPainter({
    required this.roiRect,
    required this.scanProgress,
    required this.isProcessing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Darkened translucent mask outside the ROI box
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(roiRect, const Radius.circular(14)));
    final overlayPath =
        Path.combine(PathOperation.difference, outerPath, holePath);

    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0xFF050914).withAlpha(165),
    );

    // Subtle border around ROI box
    final accent =
        isProcessing ? const Color(0xFFFFB300) : const Color(0xFF00E5FF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roiRect, const Radius.circular(14)),
      Paint()
        ..color = accent.withAlpha(110)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Corner brackets
    const double cornerLen = 24.0;
    final bracketPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final l = roiRect.left;
    final t = roiRect.top;
    final r = roiRect.right;
    final b = roiRect.bottom;

    // Top-left
    canvas.drawLine(Offset(l, t + cornerLen), Offset(l, t), bracketPaint);
    canvas.drawLine(Offset(l, t), Offset(l + cornerLen, t), bracketPaint);
    // Top-right
    canvas.drawLine(Offset(r - cornerLen, t), Offset(r, t), bracketPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cornerLen), bracketPaint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - cornerLen), Offset(l, b), bracketPaint);
    canvas.drawLine(Offset(l, b), Offset(l + cornerLen, b), bracketPaint);
    // Bottom-right
    canvas.drawLine(Offset(r - cornerLen, b), Offset(r, b), bracketPaint);
    canvas.drawLine(Offset(r, b - cornerLen), Offset(r, b), bracketPaint);

    // Animated green laser scan line inside ROI
    final laserY = t + 10 + (roiRect.height - 20) * scanProgress;
    final laserColor =
        isProcessing ? const Color(0xFFFFB300) : const Color(0xFF00E676);

    canvas.drawLine(
      Offset(l + 12, laserY),
      Offset(r - 12, laserY),
      Paint()
        ..color = laserColor.withAlpha(120)
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      Offset(l + 12, laserY),
      Offset(r - 12, laserY),
      Paint()
        ..color = laserColor
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant RoiOverlayPainter oldDelegate) {
    return oldDelegate.roiRect != roiRect ||
        oldDelegate.scanProgress != scanProgress ||
        oldDelegate.isProcessing != isProcessing;
  }
}
