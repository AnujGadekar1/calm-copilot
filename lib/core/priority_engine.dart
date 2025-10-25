// Path: lib/core/priority_engine.dart
// Advanced priority engine with object tracking and trajectory prediction

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/detection_service_tflite.dart';
import '../services/sensor_service.dart';

class SelectedEvent {
  final Detection detection;
  final double urgency;
  final String reason;
  final TrackingInfo? trackingInfo;

  SelectedEvent({
    required this.detection,
    required this.urgency,
    this.reason = '',
    this.trackingInfo,
  });
}

class TrackingInfo {
  final int trackId;
  final double velocityX;
  final double velocityY;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int frameCount;

  TrackingInfo({
    required this.trackId,
    required this.velocityX,
    required this.velocityY,
    required this.firstSeen,
    required this.lastSeen,
    required this.frameCount,
  });

  TrackingInfo copyWith({
    double? velocityX,
    double? velocityY,
    DateTime? lastSeen,
    int? frameCount,
  }) {
    return TrackingInfo(
      trackId: trackId,
      velocityX: velocityX ?? this.velocityX,
      velocityY: velocityY ?? this.velocityY,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      frameCount: frameCount ?? this.frameCount,
    );
  }
}

class TrackedObject {
  final Detection detection;
  final TrackingInfo trackingInfo;
  final Offset centerPosition;

  TrackedObject({
    required this.detection,
    required this.trackingInfo,
    required this.centerPosition,
  });
}

class PriorityEngine {
  final SensorService sensorService;
  final StreamController<SelectedEvent?> _selectedController =
      StreamController.broadcast();
  Stream<SelectedEvent?> get selectedStream => _selectedController.stream;

  // Object tracking state
  final Map<int, TrackedObject> _trackedObjects = {};
  int _nextTrackId = 0;
  DateTime? _lastProcessTime;

  // Announcement throttling
  DateTime? _lastAnnouncementTime;
  String? _lastAnnouncedLabel;
  static const Duration _minAnnouncementGap = Duration(seconds: 2);
  static const Duration _urgentAnnouncementGap = Duration(milliseconds: 500);

  // Configuration
  static const double _trackingDistanceThreshold = 100.0; // pixels
  static const int _maxMissedFrames = 5;

  PriorityEngine({required this.sensorService});

  // Enhanced class priority with risk factors
  static const Map<String, Map<String, double>> classRiskProfile = {
    "person": {"priority": 1.0, "collision_risk": 0.9, "motion_weight": 1.0},
    "bicycle": {
      "priority": 0.95,
      "collision_risk": 0.85,
      "motion_weight": 0.95,
    },
    "motorbike": {"priority": 0.9, "collision_risk": 0.9, "motion_weight": 0.9},
    "car": {"priority": 0.9, "collision_risk": 1.0, "motion_weight": 0.85},
    "truck": {"priority": 0.85, "collision_risk": 1.0, "motion_weight": 0.8},
    "bus": {"priority": 0.85, "collision_risk": 1.0, "motion_weight": 0.8},
    "dog": {"priority": 0.65, "collision_risk": 0.6, "motion_weight": 0.9},
    "cat": {"priority": 0.5, "collision_risk": 0.4, "motion_weight": 0.85},
    "chair": {"priority": 0.4, "collision_risk": 0.5, "motion_weight": 0.0},
    "table": {"priority": 0.4, "collision_risk": 0.6, "motion_weight": 0.0},
    "door": {"priority": 0.35, "collision_risk": 0.3, "motion_weight": 0.0},
    "stairs": {"priority": 0.7, "collision_risk": 0.8, "motion_weight": 0.0},
    "bench": {"priority": 0.45, "collision_risk": 0.5, "motion_weight": 0.0},
  };

  double _getClassPriority(String label) {
    return classRiskProfile[label]?["priority"] ?? 0.3;
  }

  double _getCollisionRisk(String label) {
    return classRiskProfile[label]?["collision_risk"] ?? 0.5;
  }

  double _getMotionWeight(String label) {
    return classRiskProfile[label]?["motion_weight"] ?? 0.5;
  }

  // Calculate center-weighted score (objects in center path are more urgent)
  double _centerPathScore(Rect bbox, double frameW) {
    final cx = bbox.left + bbox.width / 2.0;
    final normalizedX = (cx / frameW - 0.5).abs(); // 0 at center, 0.5 at edges

    // Strong center bias - exponential falloff
    if (normalizedX < 0.15) return 1.0; // Direct path
    if (normalizedX < 0.25) return 0.7; // Near path
    if (normalizedX < 0.35) return 0.4; // Side path
    return 0.1; // Peripheral
  }

  // Calculate motion threat score
  double _motionThreatScore(TrackedObject tracked, double frameW) {
    final vel = sqrt(
      tracked.trackingInfo.velocityX * tracked.trackingInfo.velocityX +
          tracked.trackingInfo.velocityY * tracked.trackingInfo.velocityY,
    );

    if (vel < 2.0) return 0.0; // Stationary

    // Check if moving toward center
    final cx = tracked.centerPosition.dx;
    final centerDistance = (cx - frameW / 2).abs();
    final movingTowardCenter =
        (cx < frameW / 2 && tracked.trackingInfo.velocityX > 0) ||
        (cx > frameW / 2 && tracked.trackingInfo.velocityX < 0);

    // Moving toward user (Y velocity positive in image coordinates)
    final approachingUser = tracked.trackingInfo.velocityY > 0;

    double score = min(vel / 20.0, 1.0); // Normalize velocity

    if (movingTowardCenter) score *= 1.5;
    if (approachingUser) score *= 1.8;

    return min(score, 1.0);
  }

  // Advanced urgency calculation
  double _calculateUrgency(
    TrackedObject tracked,
    double frameW,
    double userSpeed,
  ) {
    final detection = tracked.detection;
    final dist = (detection.distance ?? 5.0).clamp(0.1, 15.0);

    // Component weights
    const wDist = 0.40;
    const wMotion = 0.25;
    const wClass = 0.15;
    const wCenter = 0.15;
    const wCollision = 0.05;

    // 1. Distance score (inverse - closer = higher)
    final distScore = 1.0 / (dist * 0.5 + 0.5);

    // 2. Motion threat
    final motionScore =
        _motionThreatScore(tracked, frameW) * _getMotionWeight(detection.label);

    // 3. Class priority
    final classScore = _getClassPriority(detection.label);

    // 4. Center path score
    final centerScore = _centerPathScore(detection.bbox, frameW);

    // 5. Collision risk
    final collisionScore = _getCollisionRisk(detection.label);

    // Weighted sum
    final baseUrgency =
        (wDist * distScore) +
        (wMotion * motionScore) +
        (wClass * classScore) +
        (wCenter * centerScore) +
        (wCollision * collisionScore);

    // Apply user speed multiplier (faster movement = higher urgency)
    final speedMultiplier = 1.0 + min(userSpeed / 1.5, 0.6);

    // Apply tracking confidence boost (well-tracked objects are more reliable)
    final trackingBoost = min(tracked.trackingInfo.frameCount / 10.0, 0.15);

    final finalUrgency = min(
      (baseUrgency * speedMultiplier) + trackingBoost,
      1.0,
    );

    return finalUrgency;
  }

  // Update object tracking
  void _updateTracking(List<Detection> detections) {
    final now = DateTime.now();
    final dt = _lastProcessTime != null
        ? now.difference(_lastProcessTime!).inMilliseconds / 1000.0
        : 0.1;
    _lastProcessTime = now;

    // Mark all as not seen this frame
    final seenIds = <int>{};

    // Try to match new detections with existing tracks
    for (final detection in detections) {
      final center = Offset(
        detection.bbox.left + detection.bbox.width / 2,
        detection.bbox.top + detection.bbox.height / 2,
      );

      // Find closest track
      int? matchedId;
      double minDist = _trackingDistanceThreshold;

      for (final entry in _trackedObjects.entries) {
        if (seenIds.contains(entry.key)) continue;
        if (entry.value.detection.label != detection.label) continue;

        final dist = (entry.value.centerPosition - center).distance;
        if (dist < minDist) {
          minDist = dist;
          matchedId = entry.key;
        }
      }

      if (matchedId != null) {
        // Update existing track
        final oldTracked = _trackedObjects[matchedId]!;
        final dx = (center.dx - oldTracked.centerPosition.dx) / dt;
        final dy = (center.dy - oldTracked.centerPosition.dy) / dt;

        // Smooth velocity with exponential moving average
        final alpha = 0.3;
        final newVelX =
            alpha * dx + (1 - alpha) * oldTracked.trackingInfo.velocityX;
        final newVelY =
            alpha * dy + (1 - alpha) * oldTracked.trackingInfo.velocityY;

        _trackedObjects[matchedId] = TrackedObject(
          detection: detection,
          trackingInfo: oldTracked.trackingInfo.copyWith(
            velocityX: newVelX,
            velocityY: newVelY,
            lastSeen: now,
            frameCount: oldTracked.trackingInfo.frameCount + 1,
          ),
          centerPosition: center,
        );

        seenIds.add(matchedId);
      } else {
        // Create new track
        final trackId = _nextTrackId++;
        _trackedObjects[trackId] = TrackedObject(
          detection: detection,
          trackingInfo: TrackingInfo(
            trackId: trackId,
            velocityX: 0.0,
            velocityY: 0.0,
            firstSeen: now,
            lastSeen: now,
            frameCount: 1,
          ),
          centerPosition: center,
        );
        seenIds.add(trackId);
      }
    }

    // Remove stale tracks
    _trackedObjects.removeWhere((id, tracked) {
      if (seenIds.contains(id)) return false;
      final age = now.difference(tracked.trackingInfo.lastSeen);
      return age.inMilliseconds > (_maxMissedFrames * dt * 1000);
    });
  }

  // Check if announcement should be throttled
  bool _shouldAnnounce(String label, double urgency) {
    final now = DateTime.now();

    if (_lastAnnouncementTime == null) return true;

    final gap = urgency >= 0.85 ? _urgentAnnouncementGap : _minAnnouncementGap;

    final timeSinceLastAnnouncement = now.difference(_lastAnnouncementTime!);

    // Different object type - always announce if enough time passed
    if (_lastAnnouncedLabel != label && timeSinceLastAnnouncement > gap) {
      return true;
    }

    // Same object - only if urgent and gap passed
    if (_lastAnnouncedLabel == label) {
      if (urgency >= 0.85 &&
          timeSinceLastAnnouncement > _urgentAnnouncementGap) {
        return true;
      }
      if (timeSinceLastAnnouncement > _minAnnouncementGap) {
        return true;
      }
      return false;
    }

    return timeSinceLastAnnouncement > gap;
  }

  void _recordAnnouncement(String label) {
    _lastAnnouncementTime = DateTime.now();
    _lastAnnouncedLabel = label;
  }

  // Main processing function
  void processDetections(
    List<Detection> detections,
    double frameWidth, {
    double userSpeed = 0.0,
  }) {
    // Update object tracking
    _updateTracking(detections);

    if (_trackedObjects.isEmpty) {
      _selectedController.add(null);
      return;
    }

    // Score all tracked objects
    TrackedObject? bestTracked;
    double bestUrgency = 0.0;
    String bestReason = '';

    for (final tracked in _trackedObjects.values) {
      final urgency = _calculateUrgency(tracked, frameWidth, userSpeed);

      if (urgency > bestUrgency) {
        bestUrgency = urgency;
        bestTracked = tracked;

        // Generate reason
        final dist = tracked.detection.distance ?? 5.0;
        final vel = sqrt(
          tracked.trackingInfo.velocityX * tracked.trackingInfo.velocityX +
              tracked.trackingInfo.velocityY * tracked.trackingInfo.velocityY,
        );

        if (dist < 1.5) {
          bestReason = "Critical proximity";
        } else if (vel > 10 && tracked.trackingInfo.velocityY > 0) {
          bestReason = "Fast approaching";
        } else if (_centerPathScore(tracked.detection.bbox, frameWidth) > 0.7) {
          bestReason = "In direct path";
        } else {
          bestReason = "Priority object detected";
        }
      }
    }

    // Apply urgency threshold and filtering
    if (bestTracked == null) {
      _selectedController.add(null);
      return;
    }

    final dist = bestTracked.detection.distance ?? 5.0;

    // Filter low urgency distant objects
    if (dist > 4.0 && bestUrgency < 0.5) {
      _selectedController.add(null);
      return;
    }

    // Minimum urgency threshold
    if (bestUrgency < 0.25) {
      _selectedController.add(null);
      return;
    }

    // Check announcement throttling
    if (!_shouldAnnounce(bestTracked.detection.label, bestUrgency)) {
      // Still emit event but won't trigger new audio
      _selectedController.add(
        SelectedEvent(
          detection: bestTracked.detection,
          urgency: bestUrgency,
          reason: bestReason,
          trackingInfo: bestTracked.trackingInfo,
        ),
      );
      return;
    }

    // Record this announcement
    _recordAnnouncement(bestTracked.detection.label);

    // Emit selected event
    _selectedController.add(
      SelectedEvent(
        detection: bestTracked.detection,
        urgency: bestUrgency,
        reason: bestReason,
        trackingInfo: bestTracked.trackingInfo,
      ),
    );
  }

  // Get tracking statistics for debugging/UI
  Map<String, dynamic> getTrackingStats() {
    return {
      'tracked_objects': _trackedObjects.length,
      'next_track_id': _nextTrackId,
      'last_announcement': _lastAnnouncementTime?.toString(),
      'last_label': _lastAnnouncedLabel,
    };
  }

  void dispose() {
    _selectedController.close();
    _trackedObjects.clear();
  }
}
