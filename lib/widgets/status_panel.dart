// Path: lib/widgets/status_panel.dart
// Bottom status panel showing current navigation state

import 'package:flutter/material.dart';
import '../core/priority_engine.dart';
import 'dart:ui';

class StatusPanel extends StatelessWidget {
  final SelectedEvent? currentEvent;
  final bool isMoving;
  final int detectionCount;

  const StatusPanel({
    Key? key,
    required this.currentEvent,
    required this.isMoving,
    required this.detectionCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isAlert = currentEvent != null && currentEvent!.urgency >= 0.7;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isAlert
                ? Colors.red.withOpacity(0.4)
                : Colors.teal.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isAlert
                    ? [
                        Colors.red.withOpacity(0.3),
                        Colors.red.shade900.withOpacity(0.5),
                      ]
                    : [
                        Colors.black.withOpacity(0.6),
                        Colors.black.withOpacity(0.8),
                      ],
              ),
              border: Border.all(
                color: isAlert ? Colors.red.shade400 : Colors.teal.shade300,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatusIndicator(isAlert),
                    _buildDetectionBadge(),
                  ],
                ),

                if (currentEvent != null) ...[
                  const SizedBox(height: 16),
                  _buildEventInfo(),
                ] else ...[
                  const SizedBox(height: 12),
                  _buildClearPathInfo(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isAlert) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isAlert ? Colors.red : Colors.green,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isAlert ? Colors.red : Colors.green).withOpacity(0.5),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            isAlert ? Icons.warning : Icons.check_circle,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAlert ? "ALERT" : "CLEAR",
              style: TextStyle(
                color: isAlert ? Colors.red.shade200 : Colors.green.shade200,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              isMoving ? "Walking Mode" : "Standing",
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade300, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility, color: Colors.teal.shade300, size: 16),
          const SizedBox(width: 6),
          Text(
            "$detectionCount",
            style: TextStyle(
              color: Colors.teal.shade300,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventInfo() {
    final detection = currentEvent!.detection;
    final urgency = currentEvent!.urgency;

    return Column(
      children: [
        // Object info
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                detection.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const Spacer(),
            if (detection.distance != null)
              Row(
                children: [
                  Icon(Icons.straighten, color: Colors.white70, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    "${detection.distance!.toStringAsFixed(1)}m",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),

        const SizedBox(height: 12),

        // Urgency meter
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Urgency Level",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                Text(
                  "${(urgency * 100).toInt()}%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: urgency,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(_getUrgencyColor(urgency)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClearPathInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          color: Colors.green.shade300,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          isMoving ? "Path is clear - Continue safely" : "Standing by",
          style: TextStyle(
            color: Colors.green.shade200,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getUrgencyColor(double urgency) {
    if (urgency >= 0.85) return Colors.red;
    if (urgency >= 0.6) return Colors.orange;
    if (urgency >= 0.4) return Colors.yellow;
    return Colors.green;
  }
}
