// Path: lib/widgets/spatial_audio_indicator.dart
// Visual indicator showing directional audio cues

import 'package:flutter/material.dart';
import '../services/detection_service_tflite.dart';
import 'dart:math' as math;

class SpatialAudioIndicator extends StatefulWidget {
  final Detection detection;
  final double imageWidth;

  const SpatialAudioIndicator({
    Key? key,
    required this.detection,
    required this.imageWidth,
  }) : super(key: key);

  @override
  State<SpatialAudioIndicator> createState() => _SpatialAudioIndicatorState();
}

class _SpatialAudioIndicatorState extends State<SpatialAudioIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centerX =
        widget.detection.bbox.left + widget.detection.bbox.width / 2.0;
    final normalizedX = (centerX / widget.imageWidth).clamp(0.0, 1.0);

    // Convert to screen position (-1 left, 0 center, 1 right)
    final position = (normalizedX * 2) - 1;

    // Determine direction
    final String direction;
    final Color directionColor;
    final IconData directionIcon;

    if (position < -0.3) {
      direction = "LEFT";
      directionColor = Colors.blue;
      directionIcon = Icons.arrow_back;
    } else if (position > 0.3) {
      direction = "RIGHT";
      directionColor = Colors.orange;
      directionIcon = Icons.arrow_forward;
    } else {
      direction = "CENTER";
      directionColor = Colors.red;
      directionIcon = Icons.warning;
    }

    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    directionColor.withOpacity(0.9),
                    directionColor.withOpacity(0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: directionColor.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(directionIcon, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        direction,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (widget.detection.distance != null)
                        Text(
                          "${widget.detection.distance!.toStringAsFixed(1)}m",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
