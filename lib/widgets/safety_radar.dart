// Path: lib/widgets/safety_radar.dart
// Circular radar showing nearby objects

import 'package:flutter/material.dart';
import '../services/detection_service_tflite.dart';
import 'dart:math' as math;

class SafetyRadar extends StatelessWidget {
  final List<Detection> detections;
  final Size imageSize;
  final AnimationController radarAnimation;

  const SafetyRadar({
    Key? key,
    required this.detections,
    required this.imageSize,
    required this.radarAnimation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.teal.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade300.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Radar sweep effect
          AnimatedBuilder(
            animation: radarAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: RadarSweepPainter(
                  sweepAngle: radarAnimation.value * 2 * math.pi,
                ),
              );
            },
          ),

          // Object dots
          CustomPaint(
            painter: RadarDotsPainter(
              detections: detections,
              imageSize: imageSize,
            ),
          ),

          // Center icon
          Center(
            child: Icon(
              Icons.person_pin,
              color: Colors.teal.shade300,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class RadarSweepPainter extends CustomPainter {
  final double sweepAngle;

  RadarSweepPainter({required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw concentric circles
    final circlePaint = Paint()
      ..color = Colors.teal.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, circlePaint);
    }

    // Draw sweep
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.teal.shade300.withOpacity(0.5), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        sweepAngle - 0.5,
        0.5,
        false,
      )
      ..close();

    canvas.drawPath(path, sweepPaint);
  }

  @override
  bool shouldRepaint(RadarSweepPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle;
  }
}

class RadarDotsPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;

  RadarDotsPainter({required this.detections, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 10;

    for (final detection in detections) {
      // Calculate position
      final centerX = detection.bbox.left + detection.bbox.width / 2.0;
      final normalizedX = (centerX / imageSize.width) * 2 - 1; // -1 to 1

      // Distance determines radius (closer = outer ring)
      final distance = detection.distance ?? 5.0;
      final normalizedDist = (1.0 - (distance / 10.0).clamp(0.0, 1.0));
      final dotRadius = maxRadius * normalizedDist;

      // Angle from normalized X position
      final angle = normalizedX * math.pi / 2; // -90° to +90°

      final dotX = center.dx + dotRadius * math.sin(angle);
      final dotY = center.dy - dotRadius * math.cos(angle);

      // Color based on urgency
      final Color dotColor;
      if (distance < 1.5) {
        dotColor = Colors.red;
      } else if (distance < 3.0) {
        dotColor = Colors.orange;
      } else {
        dotColor = Colors.green;
      }

      // Draw dot with glow
      final glowPaint = Paint()
        ..color = dotColor.withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(Offset(dotX, dotY), 6, glowPaint);

      final dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(RadarDotsPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
