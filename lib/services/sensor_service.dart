// Path: lib/services/sensor_service.dart
// Advanced Sensor Service with Accelerometer, Gyroscope, and Magnetometer

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  // Sensor subscriptions
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;

  // State
  bool _isMoving = false;
  double _currentSpeed = 0.0;
  double _currentHeading = 0.0; // 0-360 degrees

  // Motion detection
  static const double MOTION_THRESHOLD = 1.5; // m/s²
  static const Duration MOTION_WINDOW = Duration(milliseconds: 500);

  final List<double> _accelMagnitudes = [];
  DateTime _lastMotionCheck = DateTime.now();

  // Orientation
  double _pitch = 0.0;
  double _roll = 0.0;
  double _yaw = 0.0;

  // Getters
  bool get isMoving => _isMoving;
  double get currentSpeed => _currentSpeed;
  double get currentHeading => _currentHeading;
  double get pitch => _pitch;
  double get roll => _roll;
  double get yaw => _yaw;

  // Stream controllers for reactive updates
  final _motionController = StreamController<bool>.broadcast();
  Stream<bool> get motionStream => _motionController.stream;

  final _orientationController = StreamController<OrientationData>.broadcast();
  Stream<OrientationData> get orientationStream =>
      _orientationController.stream;

  Future<void> initialize() async {
    try {
      // Subscribe to accelerometer
      _accelSubscription = accelerometerEvents.listen((event) {
        _processAccelerometer(event);
      });

      // Subscribe to gyroscope
      _gyroSubscription = gyroscopeEvents.listen((event) {
        _processGyroscope(event);
      });

      // Subscribe to magnetometer
      _magSubscription = magnetometerEvents.listen((event) {
        _processMagnetometer(event);
      });

      debugPrint("[SensorService] ✅ Sensors initialized");
    } catch (e) {
      debugPrint("[SensorService] ❌ Error initializing sensors: $e");
    }
  }

  void _processAccelerometer(AccelerometerEvent event) {
    // Calculate magnitude of acceleration (removing gravity)
    final magnitude = sqrt(
      pow(event.x, 2) + pow(event.y, 2) + pow(event.z - 9.81, 2),
    );

    _accelMagnitudes.add(magnitude);

    // Keep only recent measurements
    final now = DateTime.now();
    if (now.difference(_lastMotionCheck) > MOTION_WINDOW) {
      _lastMotionCheck = now;

      // Calculate average magnitude
      if (_accelMagnitudes.isNotEmpty) {
        final avgMagnitude =
            _accelMagnitudes.reduce((a, b) => a + b) / _accelMagnitudes.length;

        // Determine if moving
        final wasMoving = _isMoving;
        _isMoving = avgMagnitude > MOTION_THRESHOLD;
        _currentSpeed = avgMagnitude;

        // Emit motion state change
        if (wasMoving != _isMoving) {
          _motionController.add(_isMoving);
        }

        _accelMagnitudes.clear();
      }
    }

    // Limit buffer size
    if (_accelMagnitudes.length > 50) {
      _accelMagnitudes.removeAt(0);
    }
  }

  void _processGyroscope(GyroscopeEvent event) {
    // Update orientation rates
    _pitch +=
        event.x *
        0.01; // Simple integration (would use quaternions in production)
    _roll += event.y * 0.01;
    _yaw += event.z * 0.01;

    // Normalize angles to 0-360
    _pitch = _normalizeAngle(_pitch);
    _roll = _normalizeAngle(_roll);
    _yaw = _normalizeAngle(_yaw);

    // Emit orientation update
    _orientationController.add(
      OrientationData(pitch: _pitch, roll: _roll, yaw: _yaw),
    );
  }

  void _processMagnetometer(MagnetometerEvent event) {
    // Calculate heading from magnetometer
    final heading = atan2(event.y, event.x) * (180 / pi);
    _currentHeading = _normalizeAngle(heading);
  }

  double _normalizeAngle(double angle) {
    while (angle < 0) angle += 360;
    while (angle >= 360) angle -= 360;
    return angle;
  }

  /// Get user's current direction of movement
  MovementDirection getMovementDirection() {
    if (!_isMoving) return MovementDirection.stationary;

    // Use heading to determine direction
    if (_currentHeading >= 315 || _currentHeading < 45) {
      return MovementDirection.forward;
    } else if (_currentHeading >= 45 && _currentHeading < 135) {
      return MovementDirection.right;
    } else if (_currentHeading >= 135 && _currentHeading < 225) {
      return MovementDirection.backward;
    } else {
      return MovementDirection.left;
    }
  }

  /// Get device orientation state
  DeviceOrientation getDeviceOrientation() {
    // Determine if device is in portrait, landscape, etc.
    if (_roll.abs() < 45) {
      return DeviceOrientation.portrait;
    } else if (_roll > 45 && _roll < 135) {
      return DeviceOrientation.landscapeRight;
    } else if (_roll > 135 && _roll < 225) {
      return DeviceOrientation.portraitUpsideDown;
    } else {
      return DeviceOrientation.landscapeLeft;
    }
  }

  /// Check if user is holding device at appropriate angle
  bool isDeviceAngleAppropriate() {
    // For camera-based navigation, device should be roughly upright
    // and tilted slightly forward (30-60 degrees from vertical)
    return _pitch > 30 && _pitch < 60 && _roll.abs() < 30;
  }

  /// Get statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'is_moving': _isMoving,
      'speed': _currentSpeed.toStringAsFixed(2),
      'heading': _currentHeading.toStringAsFixed(1),
      'pitch': _pitch.toStringAsFixed(1),
      'roll': _roll.toStringAsFixed(1),
      'yaw': _yaw.toStringAsFixed(1),
    };
  }

  void dispose() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _magSubscription?.cancel();
    _motionController.close();
    _orientationController.close();
  }
}

class OrientationData {
  final double pitch;
  final double roll;
  final double yaw;

  OrientationData({required this.pitch, required this.roll, required this.yaw});
}

enum MovementDirection { stationary, forward, backward, left, right }

enum DeviceOrientation {
  portrait,
  portraitUpsideDown,
  landscapeLeft,
  landscapeRight,
}
