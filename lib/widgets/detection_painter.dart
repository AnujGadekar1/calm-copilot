// Path: lib/widgets/detection_painter.dart
// Professional detection visualization with animated boxes and depth indicators

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/detection_service_tflite.dart';
import 'dart:ui' as ui;

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;
  final Size screenSize;
  final Color boxColor;
  final double strokeWidth;

  DetectionPainter({
    required this.detections,
    required this.imageSize,
    required this.screenSize,
    this.boxColor = Colors.teal,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero || screenSize == Size.zero) return;

    for (final d in detections) {
      final scaledRect = scaleAndRotateBox(d.bbox, imageSize, size);

      // Determine box color based on distance/urgency
      final Color finalColor = _getColorForDetection(d);

      // Draw outer glow
      _drawGlow(canvas, scaledRect, finalColor);

      // Draw main bounding box with gradient
      _drawBoundingBox(canvas, scaledRect, finalColor);

      // Draw corner accents
      _drawCornerAccents(canvas, scaledRect, finalColor);

      // Draw depth indicator
      if (d.distance != null) {
        _drawDepthIndicator(canvas, scaledRect, d.distance!, finalColor);
      }

      // Draw label with professional styling
      _drawLabel(canvas, scaledRect, d, size, finalColor);
    }
  }

  Color _getColorForDetection(Detection d) {
    final distance = d.distance ?? 5.0;

    if (distance < 1.5) {
      return Colors.red; // Critical - very close
    } else if (distance < 3.0) {
      return Colors.orange; // Warning
    } else if (distance < 5.0) {
      return Colors.yellow; // Caution
    } else {
      return Colors.green; // Safe
    }
  }

  void _drawGlow(Canvas canvas, Rect rect, Color color) {
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;

    canvas.drawRect(rect, glowPaint);
  }

  void _drawBoundingBox(Canvas canvas, Rect rect, Color color) {
    // Gradient stroke
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color.withOpacity(0.9), color.withOpacity(0.6)],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(rect, paint);

    // Inner shadow effect
    final innerPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRect(rect, innerPaint);
  }

  void _drawCornerAccents(Canvas canvas, Rect rect, Color color) {
    final cornerLength = math.min(rect.width, rect.height) * 0.15;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.5
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, cornerLength),
      paint,
    );

    // Top-right
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLength),
      paint,
    );
  }

  void _drawDepthIndicator(
    Canvas canvas,
    Rect rect,
    double distance,
    Color color,
  ) {
    final indicatorWidth = rect.width * 0.15;
    final indicatorHeight = rect.height * 0.6;

    final indicatorRect = Rect.fromLTWH(
      rect.right + 8,
      rect.top + (rect.height - indicatorHeight) / 2,
      indicatorWidth,
      indicatorHeight,
    );

    // Background
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(indicatorRect, const Radius.circular(4)),
      bgPaint,
    );

    // Fill level (inverse of distance - closer = more fill)
    final fillLevel = (1.0 - (distance / 10.0).clamp(0.0, 1.0));
    final fillHeight = indicatorHeight * fillLevel;

    final fillRect = Rect.fromLTWH(
      indicatorRect.left,
      indicatorRect.bottom - fillHeight,
      indicatorRect.width,
      fillHeight,
    );

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.6), color],
      ).createShader(indicatorRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, const Radius.circular(4)),
      fillPaint,
    );

    // Border
    final borderPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(indicatorRect, const Radius.circular(4)),
      borderPaint,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Rect rect,
    Detection d,
    Size size,
    Color color,
  ) {
    final label = d.label.toUpperCase();
    final conf = (d.confidence * 100).toInt();
    final distText = d.distance != null
        ? "${d.distance!.toStringAsFixed(1)}m"
        : "";

    // Create text painter for label
    final labelSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.8),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );

    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();

    // Create text painter for info
    final infoSpan = TextSpan(
      text: "$conf% • $distText",
      style: TextStyle(
        color: Colors.white.withOpacity(0.9),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.8),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );

    final infoPainter = TextPainter(
      text: infoSpan,
      textDirection: TextDirection.ltr,
    );
    infoPainter.layout();

    // Calculate background size
    final padding = 8.0;
    final maxWidth = math.max(labelPainter.width, infoPainter.width);
    final bgWidth = maxWidth + padding * 2;
    final bgHeight = labelPainter.height + infoPainter.height + padding * 2 + 4;

    // Position (above box, or below if not enough space)
    double bgLeft = rect.left.clamp(0.0, size.width - bgWidth);
    double bgTop = rect.top - bgHeight - 8;

    if (bgTop < 0) {
      bgTop = rect.bottom + 8;
    }

    final bgRect = Rect.fromLTWH(bgLeft, bgTop, bgWidth, bgHeight);

    // Draw background with gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.95), color.withOpacity(0.85)],
      ).createShader(bgRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      bgPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      borderPaint,
    );

    // Draw text
    labelPainter.paint(canvas, Offset(bgLeft + padding, bgTop + padding));

    infoPainter.paint(
      canvas,
      Offset(bgLeft + padding, bgTop + padding + labelPainter.height + 4),
    );
  }

  Rect scaleAndRotateBox(Rect boundingBox, Size imageSize, Size screenSize) {
    final Size rotatedImageSize = Size(imageSize.height, imageSize.width);

    final Rect rotatedBoundingBox = Rect.fromLTRB(
      imageSize.height - boundingBox.bottom,
      boundingBox.left,
      imageSize.height - boundingBox.top,
      boundingBox.right,
    );

    final double scaleX = screenSize.width / rotatedImageSize.width;
    final double scaleY = screenSize.height / rotatedImageSize.height;
    final double scale = math.max(scaleX, scaleY);

    final double newImageWidth = rotatedImageSize.width * scale;
    final double newImageHeight = rotatedImageSize.height * scale;

    final double offsetX = (screenSize.width - newImageWidth) / 2;
    final double offsetY = (screenSize.height - newImageHeight) / 2;

    return Rect.fromLTRB(
      rotatedBoundingBox.left * scale + offsetX,
      rotatedBoundingBox.top * scale + offsetY,
      rotatedBoundingBox.right * scale + offsetX,
      rotatedBoundingBox.bottom * scale + offsetY,
    );
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.boxColor != boxColor;
  }
}
