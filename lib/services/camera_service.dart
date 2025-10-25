// Path: lib/services/camera_service.dart
// OPTIMIZED VERSION - Fixes BufferQueueProducer timeout warnings

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _cameraController;
  CameraController? get controller => _cameraController;

  final _imageStreamController = StreamController<CameraImage>.broadcast();
  Stream<CameraImage> get imageStream => _imageStreamController.stream;

  bool _isStreaming = false;
  bool _isProcessingFrame = false; // NEW: Prevent buffer overflow
  int _droppedFrames = 0; // NEW: Track performance

  Future<CameraDescription> initialize({bool useFront = false}) async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      debugPrint("[CameraService] ❌ Camera permission not granted");
      throw Exception("Camera permission not granted");
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint("[CameraService] ❌ No cameras available");
      throw Exception("No cameras available");
    }

    final camera = useFront
        ? cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first,
          )
        : cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );

    // OPTIMIZED: Choose optimal format and resolution
    final imageFormat = Platform.isAndroid
        ? ImageFormatGroup.yuv420
        : ImageFormatGroup.bgra8888;

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium, // Medium is optimal for real-time processing
      enableAudio: false,
      imageFormatGroup: imageFormat,
      // NEW: Optimize FPS for processing capability
      fps: 30, // Limit to 30 FPS max
    );

    try {
      await _cameraController!.initialize();

      // NEW: Set optimal focus and exposure for indoor/outdoor
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setExposureMode(ExposureMode.auto);

      debugPrint("[CameraService] ✅ Camera initialized (${camera.name})");
      debugPrint(
        "[CameraService] 📊 Resolution: ${_cameraController!.value.previewSize}",
      );

      await _startStream();
      return camera;
    } catch (e, st) {
      debugPrint("[CameraService] ⚠️ Error initializing camera: $e\n$st");
      throw Exception("Error initializing camera: $e");
    }
  }

  Future<void> _startStream() async {
    if (_cameraController == null) return;
    if (_isStreaming) return;

    try {
      await _cameraController!.startImageStream((CameraImage image) {
        // NEW: Drop frames if processing is behind to prevent buffer overflow
        if (_isProcessingFrame) {
          _droppedFrames++;
          // Only log every 500 frames to reduce console spam
          if (_droppedFrames % 500 == 0) {
            debugPrint(
              "[CameraService] ℹ️ Dropped $_droppedFrames frames (optimizing performance)",
            );
          }
          return;
        }

        _isProcessingFrame = true;

        if (!_imageStreamController.isClosed) {
          _imageStreamController.add(image);
        }

        // Reset flag after small delay to allow processing
        Future.delayed(const Duration(milliseconds: 50), () {
          _isProcessingFrame = false;
        });
      });

      _isStreaming = true;
      debugPrint("[CameraService] 🎥 Image stream started");
    } catch (e) {
      debugPrint("[CameraService] ⚠️ Could not start stream: $e");
    }
  }

  Future<void> stopStream() async {
    if (!_isStreaming || _cameraController == null) return;
    try {
      await _cameraController!.stopImageStream();
      _isStreaming = false;
      _isProcessingFrame = false;
      debugPrint("[CameraService] ⏸️ Stream stopped");
    } catch (e) {
      debugPrint("[CameraService] ⚠️ Error stopping stream: $e");
    }
  }

  // NEW: Get performance statistics
  Map<String, dynamic> getStats() {
    return {
      'is_streaming': _isStreaming,
      'dropped_frames': _droppedFrames,
      'resolution': _cameraController?.value.previewSize.toString() ?? 'N/A',
    };
  }

  // NEW: Reset dropped frame counter
  void resetStats() {
    _droppedFrames = 0;
  }

  Future<void> dispose() async {
    debugPrint("[CameraService] ♻️ Disposing camera");
    try {
      await stopStream();
      await _cameraController?.dispose();
    } catch (e) {
      debugPrint("[CameraService] ⚠️ Dispose error: $e");
    } finally {
      await _imageStreamController.close();
    }
  }
}
