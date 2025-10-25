// Path: lib/utils/distance_calculator.dart
// Advanced distance calculation using multiple estimation methods

import 'dart:math';
import 'package:flutter/material.dart';

class DistanceCalculator {
  // Camera parameters (calibration values)
  static const double FOCAL_LENGTH_MM = 4.25; // Typical smartphone camera
  static const double SENSOR_HEIGHT_MM = 5.76; // Typical 1/2.55" sensor

  // Real-world object heights (in meters)
  static const Map<String, double> KNOWN_OBJECT_HEIGHTS = {
    'person': 1.70, // Average human height
    'car': 1.50, // Average car height
    'bus': 3.20,
    'truck': 3.50,
    'bicycle': 1.10,
    'motorbike': 1.20,
    'chair': 0.85,
    'table': 0.75,
    'dog': 0.60, // Medium dog
    'cat': 0.30,
    'bench': 0.50,
    'traffic light': 3.00,
    'stop sign': 2.40,
    'door': 2.10,
    'bottle': 0.25,
    'cup': 0.12,
    'laptop': 0.35,
    'backpack': 0.45,
    'handbag': 0.30,
    'suitcase': 0.60,
  };

  /// Method 1: Height-based estimation (most accurate)
  static double calculateDistanceByHeight({
    required String objectLabel,
    required Rect bbox,
    required Size imageSize,
  }) {
    final realHeight = KNOWN_OBJECT_HEIGHTS[objectLabel.toLowerCase()];
    if (realHeight == null) {
      // Fallback to simple method
      return calculateDistanceSimple(bbox: bbox, imageSize: imageSize);
    }

    // Calculate focal length in pixels
    final focalLengthPixels =
        (FOCAL_LENGTH_MM * imageSize.height) / SENSOR_HEIGHT_MM;

    // Object height in pixels
    final objectHeightPixels = bbox.height;

    // Distance = (Real Height × Focal Length) / Object Height in Pixels
    final distance = (realHeight * focalLengthPixels) / objectHeightPixels;

    return distance.clamp(0.1, 50.0); // Clamp to reasonable range
  }

  /// Method 2: Area-based estimation
  static double calculateDistanceByArea({
    required String objectLabel,
    required Rect bbox,
    required Size imageSize,
  }) {
    // Approximate real-world dimensions
    final Map<String, double> typicalAreas = {
      'person': 0.6, // ~0.5m width × 1.7m height frontal area
      'car': 6.0, // ~2m × 3m
      'chair': 0.4,
      'table': 1.5,
      'dog': 0.3,
    };

    final typicalArea = typicalAreas[objectLabel.toLowerCase()];
    if (typicalArea == null) {
      return calculateDistanceSimple(bbox: bbox, imageSize: imageSize);
    }

    // Calculate bbox area in image
    final bboxArea = bbox.width * bbox.height;
    final imageArea = imageSize.width * imageSize.height;
    final bboxRatio = bboxArea / imageArea;

    // Inverse square relationship
    final distance = sqrt(typicalArea / bboxRatio) * 10;

    return distance.clamp(0.1, 50.0);
  }

  /// Method 3: Simple calibrated estimation (fallback)
  static double calculateDistanceSimple({
    required Rect bbox,
    required Size imageSize,
    double calibrationFactor = 0.35,
  }) {
    final bboxHeightPx = bbox.height.clamp(1.0, imageSize.height);
    final estimatedMeters =
        (imageSize.height / bboxHeightPx) * calibrationFactor;
    return estimatedMeters.clamp(0.1, 50.0);
  }

  /// Method 4: Perspective-based estimation
  static double calculateDistanceByPerspective({
    required Rect bbox,
    required Size imageSize,
  }) {
    // Objects lower in frame are typically closer
    final centerY = bbox.top + bbox.height / 2;
    final normalizedY = centerY / imageSize.height; // 0 = top, 1 = bottom

    // Objects at bottom are closer
    final verticalFactor = 1.0 - normalizedY;

    // Combine with size
    final sizeFactor = bbox.height / imageSize.height;

    // Distance decreases with size and vertical position
    final distance = (1.0 / (sizeFactor * 3)) * (1.0 + verticalFactor * 0.5);

    return distance.clamp(0.1, 50.0);
  }

  /// Method 5: Hybrid approach (recommended)
  static double calculateDistanceHybrid({
    required String objectLabel,
    required Rect bbox,
    required Size imageSize,
    double confidence = 1.0,
  }) {
    // Weight different methods based on confidence and object type
    double distance;

    if (KNOWN_OBJECT_HEIGHTS.containsKey(objectLabel.toLowerCase()) &&
        confidence > 0.6) {
      // Use height-based method for known objects with good confidence
      distance = calculateDistanceByHeight(
        objectLabel: objectLabel,
        bbox: bbox,
        imageSize: imageSize,
      );

      // Adjust with perspective
      final perspectiveDistance = calculateDistanceByPerspective(
        bbox: bbox,
        imageSize: imageSize,
      );

      // Weighted average (70% height-based, 30% perspective)
      distance = distance * 0.7 + perspectiveDistance * 0.3;
    } else {
      // Use simple method for unknown objects
      distance = calculateDistanceSimple(bbox: bbox, imageSize: imageSize);
    }

    return _applyConfidenceAdjustment(distance, confidence);
  }

  /// Apply confidence-based adjustment
  static double _applyConfidenceAdjustment(double distance, double confidence) {
    // Lower confidence = add uncertainty margin
    final uncertaintyMargin = 1.0 + (1.0 - confidence) * 0.5;
    return (distance * uncertaintyMargin).clamp(0.1, 50.0);
  }

  /// Get distance category for UI
  static DistanceCategory getDistanceCategory(double? distance) {
    if (distance == null) return DistanceCategory.unknown;

    if (distance < 1.0) return DistanceCategory.veryClose;
    if (distance < 2.5) return DistanceCategory.close;
    if (distance < 5.0) return DistanceCategory.medium;
    if (distance < 10.0) return DistanceCategory.far;
    return DistanceCategory.veryFar;
  }

  /// Get human-readable distance description
  static String getDistanceDescription(double? distance) {
    if (distance == null) return "Unknown distance";

    final category = getDistanceCategory(distance);

    switch (category) {
      case DistanceCategory.veryClose:
        return "Very close (${distance.toStringAsFixed(1)}m)";
      case DistanceCategory.close:
        return "Close (${distance.toStringAsFixed(1)}m)";
      case DistanceCategory.medium:
        return "Medium distance (${distance.toStringAsFixed(1)}m)";
      case DistanceCategory.far:
        return "Far (${distance.toStringAsFixed(0)}m)";
      case DistanceCategory.veryFar:
        return "Very far (${distance.toStringAsFixed(0)}m)";
      case DistanceCategory.unknown:
        return "Unknown distance";
    }
  }

  /// Calibrate distance calculator with known measurement
  static double calibrate({
    required double measuredDistance,
    required Rect bbox,
    required Size imageSize,
  }) {
    // Calculate what calibration factor would give the measured distance
    final bboxHeightPx = bbox.height.clamp(1.0, imageSize.height);
    final calculatedFactor =
        (measuredDistance * bboxHeightPx) / imageSize.height;
    return calculatedFactor;
  }

  /// Estimate confidence in distance calculation
  static double getDistanceConfidence({
    required String objectLabel,
    required Rect bbox,
    required Size imageSize,
    required double detectionConfidence,
  }) {
    double confidence = detectionConfidence;

    // Higher confidence for known objects
    if (KNOWN_OBJECT_HEIGHTS.containsKey(objectLabel.toLowerCase())) {
      confidence *= 1.2;
    }

    // Lower confidence for very small objects (far away)
    final sizeRatio = bbox.height / imageSize.height;
    if (sizeRatio < 0.05) {
      confidence *= 0.7;
    }

    // Lower confidence for partially visible objects
    if (bbox.left < 0 ||
        bbox.right > imageSize.width ||
        bbox.top < 0 ||
        bbox.bottom > imageSize.height) {
      confidence *= 0.8;
    }

    return confidence.clamp(0.0, 1.0);
  }
}

enum DistanceCategory {
  veryClose, // < 1m - Immediate danger
  close, // 1-2.5m - Caution zone
  medium, // 2.5-5m - Awareness zone
  far, // 5-10m - Information
  veryFar, // > 10m - Background
  unknown, // Cannot determine
}

/// Extension for easy distance calculation on Detection objects
extension DistanceCalculation on Rect {
  double calculateDistance({
    required String label,
    required Size imageSize,
    double confidence = 1.0,
  }) {
    return DistanceCalculator.calculateDistanceHybrid(
      objectLabel: label,
      bbox: this,
      imageSize: imageSize,
      confidence: confidence,
    );
  }
}
