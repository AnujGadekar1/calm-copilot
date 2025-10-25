// Path: lib/widgets/semantic_radar_painter.dart
//
// NEW WIDGET:
// - This visualizes the "3D Mental Map" for the judges.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/detection_service_tflite.dart'; // Uses TFLite's Detection class
import '../core/priority_engine.dart'; // Import SelectedEvent

class SemanticRadarPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;
  final SelectedEvent? currentEvent;

  static const double maxDistance = 7.0; // Max meters to show on radar

  SemanticRadarPainter({
    required this.detections,
    required this.imageSize,
    this.currentEvent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 20);
    final maxRadius = size.height * 0.9;

    final linePaint = Paint()
      ..color = Colors.teal.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw background radar lines
    canvas.drawCircle(center, maxRadius * (1 / 3), linePaint);
    canvas.drawCircle(center, maxRadius * (2 / 3), linePaint);
    canvas.drawCircle(center, maxRadius, linePaint);

    // Draw "self" icon
    final selfPaint = Paint()..color = Colors.teal;
    canvas.drawCircle(center, 8.0, selfPaint);
    canvas.drawRect(
      Rect.fromCenter(center: center.translate(0, 12), width: 16, height: 4),
      selfPaint,
    );

    if (imageSize == Size.zero) return;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final d in detections) {
      final dist = (d.distance ?? maxDistance).clamp(0.5, maxDistance);
      final centerX = (d.bbox.left + d.bbox.width / 2.0);

      // Map horizontal position (0 to imageSize.width) to an angle
      final xRatio = centerX / imageSize.width;
      final angle = (xRatio - 0.5) * (math.pi / 2.5); // ~72 deg FOV

      // Map distance to radius
      final radius = (dist / maxDistance) * maxRadius;

      // Convert polar (angle, radius) to cartesian (x, y)
      final y = center.dy - (radius * math.cos(angle));
      final x = center.dx + (radius * math.sin(angle));

      final offset = Offset(x, y);

      // Check if this is the *current* highlighted event
      final isSelected = d.bbox == currentEvent?.detection.bbox;
      final color = isSelected ? Colors.red.shade400 : Colors.teal.shade200;
      final dotRadius = isSelected ? 8.0 : 5.0;

      final dotPaint = Paint()..color = color;
      canvas.drawCircle(offset, dotRadius, dotPaint);

      // Draw label
      final label = "${d.label} (${dist.toStringAsFixed(1)}m)";
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          backgroundColor: Colors.black.withOpacity(0.6),
        ),
      );
      textPainter.text = textSpan;
      textPainter.layout();
      textPainter.paint(canvas, offset.translate(8, -textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant SemanticRadarPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.currentEvent != currentEvent;
  }
}
