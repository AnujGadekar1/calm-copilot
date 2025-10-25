// Path: lib/widgets/debug_dashboard.dart
// Optional Debug Dashboard for Hackathon Demo

import 'package:flutter/material.dart';
import 'dart:async';

class DebugDashboard extends StatefulWidget {
  final Map<String, dynamic> Function() getStats;

  const DebugDashboard({Key? key, required this.getStats}) : super(key: key);

  @override
  State<DebugDashboard> createState() => _DebugDashboardState();
}

class _DebugDashboardState extends State<DebugDashboard> {
  Timer? _updateTimer;
  Map<String, dynamic> _stats = {};
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _stats = widget.getStats();
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withOpacity(0.5), width: 1),
          ),
          child: _isExpanded ? _buildExpandedView() : _buildCompactView(),
        ),
      ),
    );
  }

  Widget _buildCompactView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, color: Colors.teal.shade300, size: 20),
        const SizedBox(width: 8),
        Text(
          'Stats',
          style: TextStyle(
            color: Colors.teal.shade300,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildStatRow('FPS', _stats['fps']?.toStringAsFixed(1) ?? '--'),
        _buildStatRow('Objects', _stats['detection_count']?.toString() ?? '0'),
        _buildStatRow('Dropped', _stats['dropped_frames']?.toString() ?? '0'),
        _buildStatRow('Motion', _stats['is_moving'] == true ? 'Yes' : 'No'),
        _buildStatRow('Speed', _stats['speed']?.toStringAsFixed(1) ?? '0.0'),
        if (_stats['urgency'] != null)
          _buildStatRow('Urgency', '${(_stats['urgency'] * 100).toInt()}%'),
        const SizedBox(height: 8),
        _buildHealthIndicator(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.analytics_outlined, color: Colors.teal.shade300, size: 20),
        const SizedBox(width: 8),
        Text(
          'Performance Monitor',
          style: TextStyle(
            color: Colors.teal.shade300,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthIndicator() {
    final droppedFrames = _stats['dropped_frames'] ?? 0;
    final fps = _stats['fps'] ?? 0.0;

    Color healthColor;
    String healthText;
    IconData healthIcon;

    if (fps > 15 && droppedFrames < 100) {
      healthColor = Colors.green;
      healthText = 'Excellent';
      healthIcon = Icons.check_circle;
    } else if (fps > 10 && droppedFrames < 500) {
      healthColor = Colors.orange;
      healthText = 'Good';
      healthIcon = Icons.warning_amber_rounded;
    } else {
      healthColor = Colors.red;
      healthText = 'Poor';
      healthIcon = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: healthColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: healthColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(healthIcon, color: healthColor, size: 16),
          const SizedBox(width: 6),
          Text(
            healthText,
            style: TextStyle(
              color: healthColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
