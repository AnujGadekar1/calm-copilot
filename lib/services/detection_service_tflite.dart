// File: lib/services/detection_service_tflite.dart
// (Corrected: Update model path, ensure enums are correct for tflite_flutter ^0.10.4)

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For Rect
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// NOTE: tflite_flutter_helper_plus is NOT used, avoiding its enums

/// Represents a single object detection.
class Detection {
  final String label;
  final double confidence; // 0.0 to 1.0
  final Rect bbox; // Bounding box in original image coordinates (e.g., 640x480)
  final double? distance; // Estimated distance in meters

  Detection({
    required this.label,
    required this.confidence,
    required this.bbox,
    this.distance,
  });

  @override
  String toString() {
    // ... (toString implementation remains the same) ...
    return 'Detection(label: $label, conf: ${(confidence * 100).toStringAsFixed(1)}%, '
        'bbox: [${bbox.left.toStringAsFixed(0)}, ${bbox.top.toStringAsFixed(0)}, '
        '${bbox.width.toStringAsFixed(0)}, ${bbox.height.toStringAsFixed(0)}], '
        'dist: ${distance?.toStringAsFixed(2)}m)';
  }
}

/// Service for running TFLite object detection on a camera stream.
class DetectionServiceTFLite {
  final Stream<CameraImage> cameraStream;
  final int frameSkip; // Process every N+1 frames (0 = process all)
  final bool tryUseGpuDelegate;

  final StreamController<List<Detection>> _detectionsController =
      StreamController.broadcast();
  Stream<List<Detection>> get detectionsStream => _detectionsController.stream;

  bool _isProcessing = false;
  int _frameCount = 0;
  bool _isInitialized = false;

  Interpreter? _interpreter;
  List<String> _labels = [];

  // --- Configuration ---
  // !!!!! IMPORTANT: REPLACE THIS FILENAME with your actual model file !!!!!
  // !!!!! (e.g., 'Yolo-v8-Detection.tflite' or 'yolov5nu_float32.tflite') !!!!!
  static const String _modelAssetPath =
      'assets/models/YOUR_MODEL_FILENAME.tflite';
  // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  static const String _labelAssetPath =
      'assets/models/labels.txt'; // Ensure this matches

  static const double CONF_THRESHOLD = 0.35;
  static const double IOU_THRESHOLD = 0.45;
  static const double DISTANCE_FACTOR = 0.45;

  int _inputBatch = 1,
      _inputHeight = 640,
      _inputWidth = 640,
      _inputChannels = 3;

  DetectionServiceTFLite({
    required this.cameraStream,
    this.frameSkip = 3, // Default: process every 4th frame
    this.tryUseGpuDelegate = true,
  }) {
    _initialize();
    cameraStream.listen(
      _onCameraImage,
      onError: (e) {
        debugPrint("[TFLiteDetection] ⚠️ Camera stream error: $e");
      },
      cancelOnError: false,
    );
  }

  Future<void> _initialize() async {
    debugPrint("[TFLiteDetection] Initializing...");
    try {
      final options = InterpreterOptions()..threads = 4;

      if (tryUseGpuDelegate) {
        try {
          final gpuDelegate = GpuDelegateV2(options: GpuDelegateOptionsV2());
          options.addDelegate(gpuDelegate);
          debugPrint("[TFLiteDetection] ✅ GPU delegate added");
        } catch (e) {
          debugPrint(
            "[TFLiteDetection] ⚠️ GPU delegate unavailable: $e. Using CPU.",
          );
        }
      } else {
        debugPrint("[TFLiteDetection] GPU delegate disabled. Using CPU.");
      }

      _interpreter = await Interpreter.fromAsset(
        _modelAssetPath,
        options: options,
      );
      _interpreter!.allocateTensors();
      debugPrint(
        "[TFLiteDetection] ✅ Interpreter loaded & tensors allocated for $_modelAssetPath",
      );

      final inputTensors = _interpreter!.getInputTensors();
      if (inputTensors.isEmpty) throw Exception("Model has no input tensors.");
      final shape = inputTensors.first.shape;
      // Dynamically set input size based on model
      if (shape.length == 4 && shape[0] == 1 && shape[3] == 3) {
        _inputBatch = shape[0];
        _inputHeight = shape[1];
        _inputWidth = shape[2];
        _inputChannels = shape[3];
        debugPrint(
          "[TFLiteDetection] Input shape cached: $_inputBatch x $_inputHeight x $_inputWidth x $_inputChannels",
        );
      } else {
        debugPrint(
          "[TFLiteDetection] ⚠️ Unexpected input shape: $shape. Check model compatibility. Using default 640x640.",
        );
        _inputHeight = 640;
        _inputWidth = 640; // Fallback - MIGHT CAUSE ERRORS!
      }

      final rawLabels = await rootBundle.loadString(_labelAssetPath);
      _labels = rawLabels
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      debugPrint(
        "[TFLiteDetection] ✅ Labels loaded (${_labels.length}) from $_labelAssetPath",
      );

      _isInitialized = true;
      debugPrint("[TFLiteDetection] ✅ Initialization Complete.");
    } catch (e, st) {
      debugPrint("[TFLiteDetection] ❌ Initialization failed: $e\n$st");
      _interpreter = null;
      _isInitialized = false;
    }
  }

  void _onCameraImage(CameraImage image) async {
    _frameCount++;
    if (!_isInitialized || _interpreter == null || _isProcessing) return;
    if (_frameCount % (frameSkip + 1) != 0) return;

    _isProcessing = true;
    // final Stopwatch stopwatch = Stopwatch()..start(); // Uncomment for timing

    try {
      final inputTensor = await compute(_preprocessImage, {
        'image': image,
        'targetWidth': _inputWidth,
        'targetHeight': _inputHeight,
      });
      // final preprocessTime = stopwatch.elapsedMilliseconds;

      if (inputTensor == null) {
        throw Exception("Preprocessing returned null");
      }

      // stopwatch.reset();
      final outputs = _runInference(inputTensor);
      // final inferenceTime = stopwatch.elapsedMilliseconds;

      // stopwatch.reset();
      final detections = _parseDetections(outputs, image.width, image.height);
      // final postprocessTime = stopwatch.elapsedMilliseconds;

      if (!_detectionsController.isClosed) {
        _detectionsController.add(detections);
      }

      // if (_frameCount % 30 == 0) { // Log timing occasionally
      //   debugPrint("[TFLiteDetection Timing] Pre: ${preprocessTime}ms, Inf: ${inferenceTime}ms, Post: ${postprocessTime}ms");
      // }
    } catch (e, st) {
      debugPrint("[TFLiteDetection] ⚠️ Frame processing error: $e\n$st");
    } finally {
      _isProcessing = false; // Release lock reliably
      // stopwatch.stop(); // Stop timing if uncommented
    }
  }

  // --- Preprocessing Static Function (for compute isolate) ---
  static Float32List? _preprocessImage(Map<String, dynamic> args) {
    final CameraImage image = args['image'];
    final int targetWidth = args['targetWidth'];
    final int targetHeight = args['targetHeight'];
    try {
      final rgbBytes = _yuv420ToRgb(image);
      if (rgbBytes.isEmpty) throw Exception("YUV conversion failed.");
      final resizedBytes = _resizeRgbNearest(
        src: rgbBytes,
        srcW: image.width,
        srcH: image.height,
        dstW: targetWidth,
        dstH: targetHeight,
      );
      if (resizedBytes.isEmpty) throw Exception("Resize failed.");
      return _toFloat32NHWC(resizedBytes, targetHeight, targetWidth);
    } catch (e) {
      debugPrint("[TFLiteDetection Compute] ⚠️ Preprocessing error: $e");
      return null;
    }
  }

  // --- Image Conversion and Preprocessing Helpers (Static) ---
  static Uint8List _yuv420ToRgb(CameraImage image) {
    /* ... same robust implementation ... */
    final w = image.width;
    final h = image.height;
    if (image.planes.length < 3 ||
        image.planes[0].bytes.isEmpty ||
        image.planes[1].bytes.isEmpty ||
        image.planes[2].bytes.isEmpty)
      return Uint8List(0);
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final out = Uint8List(w * h * 3);
    int outIndex = 0;
    for (int y = 0; y < h; y++) {
      final yRowStart = y * yRowStride;
      final uvRowStart = (y ~/ 2) * uvRowStride;
      for (int x = 0; x < w; x++) {
        final yIndex = yRowStart + x;
        if (yIndex >= yBytes.length) continue;
        final uvx = x ~/ 2;
        final uvIndex = uvRowStart + uvx * uvPixelStride;
        if (uvIndex >= uBytes.length || uvIndex >= vBytes.length) continue;
        final yValue = yBytes[yIndex] & 0xFF;
        final uValue = (uBytes[uvIndex] & 0xFF) - 128;
        final vValue = (vBytes[uvIndex] & 0xFF) - 128;
        int r = (yValue + 1.13983 * vValue).round();
        int g = (yValue - 0.39465 * uValue - 0.58060 * vValue).round();
        int b = (yValue + 2.03211 * uValue).round();
        out[outIndex++] = r.clamp(0, 255);
        out[outIndex++] = g.clamp(0, 255);
        out[outIndex++] = b.clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List _resizeRgbNearest({
    required Uint8List src,
    required int srcW,
    required int srcH,
    required int dstW,
    required int dstH,
  }) {
    /* ... same robust implementation ... */
    if (srcW <= 0 ||
        srcH <= 0 ||
        dstW <= 0 ||
        dstH <= 0 ||
        src.length != srcW * srcH * 3)
      return Uint8List(0);
    final dst = Uint8List(dstW * dstH * 3);
    final double xRatio = srcW / dstW;
    final double yRatio = srcH / dstH;
    int dstIndex = 0;
    for (int dy = 0; dy < dstH; dy++) {
      final int sy = (dy * yRatio).floor().clamp(0, srcH - 1);
      final int srcRowStart = sy * srcW * 3;
      for (int dx = 0; dx < dstW; dx++) {
        final int sx = (dx * xRatio).floor().clamp(0, srcW - 1);
        final int srcIndex = srcRowStart + sx * 3;
        if (srcIndex + 2 < src.length) {
          dst[dstIndex++] = src[srcIndex];
          dst[dstIndex++] = src[srcIndex + 1];
          dst[dstIndex++] = src[srcIndex + 2];
        } else {
          dst[dstIndex++] = 0;
          dst[dstIndex++] = 0;
          dst[dstIndex++] = 0;
        }
      }
    }
    return dst;
  }

  static Float32List _toFloat32NHWC(Uint8List rgbBytes, int h, int w) {
    /* ... same robust implementation ... */
    final int count = h * w * 3;
    if (rgbBytes.length != count)
      throw Exception("toFloat32NHWC size mismatch");
    final floats = Float32List(count);
    for (int i = 0; i < count; i++) {
      floats[i] = rgbBytes[i] / 255.0;
    }
    return floats;
  }

  // --- Inference and Postprocessing ---
  List<List<double>> _runInference(Float32List inputNHWC) {
    /* ... same robust implementation ... */
    if (_interpreter == null) return [];
    final inputShape = [_inputBatch, _inputHeight, _inputWidth, _inputChannels];
    if (inputNHWC.length != inputShape.reduce((a, b) => a * b)) return [];
    final inputs = [inputNHWC.buffer.asFloat32List().reshape(inputShape)];
    final outputs = <int, Object>{};
    final outputTensors = _interpreter!.getOutputTensors();
    for (int i = 0; i < outputTensors.length; i++) {
      final tensor = outputTensors[i];
      outputs[i] = List.filled(
        tensor.shape.reduce((a, b) => a * b),
        0.0,
      ).reshape(tensor.shape);
    }
    try {
      _interpreter!.runForMultipleInputs(inputs, outputs);
    } catch (e, st) {
      debugPrint("[TFLiteDetection] ⚠️ Inference error: $e\n$st.");
      return [];
    }
    final resultLists = <List<double>>[];
    for (final buffer in outputs.values) {
      if (buffer is List) {
        final List<num> flatNumList = [];
        final queue = List<dynamic>.from(buffer);
        while (queue.isNotEmpty) {
          final item = queue.removeAt(0);
          if (item is List) {
            queue.addAll(item);
          } else if (item is num) {
            flatNumList.add(item);
          }
        }
        resultLists.add(
          List<double>.from(flatNumList.map((e) => e.toDouble())),
        );
      } else {
        debugPrint(
          "[TFLiteDetection] ⚠️ Unexpected output buffer type: ${buffer.runtimeType}",
        );
      }
    }
    return resultLists;
  }

  List<Detection> _parseDetections(
    List<List<double>> outputs,
    int originalImageWidth,
    int originalImageHeight,
  ) {
    /* ... same robust implementation ... */
    final detections = <Detection>[];
    if (outputs.isEmpty ||
        outputs.first.isEmpty ||
        _labels.isEmpty ||
        _interpreter == null)
      return detections;
    final List<double> outputData = outputs.first;
    final int numClasses = _labels.length;
    final int elementsPerBox = 4 + 1 + numClasses;
    final outputTensors = _interpreter!.getOutputTensors();
    if (outputTensors.isEmpty) return detections;
    final shape = outputTensors.first.shape;
    if (shape.length != 3 || shape[0] != 1 || shape[1] != elementsPerBox) {
      debugPrint(
        "[TFLiteDetection] ⚠️ Unexpected output shape $shape. Trying fallback parser.",
      );
      return _parseDetectionsSimpleStride(
        outputs,
        originalImageWidth,
        originalImageHeight,
      );
    }
    final int numBoxes = shape[2];
    if (outputData.length != elementsPerBox * numBoxes) {
      debugPrint(
        "[TFLiteDetection] ⚠️ Output data length mismatch! Shape: $shape. Trying fallback.",
      );
      return _parseDetectionsSimpleStride(
        outputs,
        originalImageWidth,
        originalImageHeight,
      );
    }
    final coordsOffset = 0;
    final confOffset = 4 * numBoxes;
    final classesOffset = 5 * numBoxes;
    for (int i = 0; i < numBoxes; i++) {
      final int confIndex = confOffset + i;
      if (confIndex >= outputData.length) continue;
      final double confidence = outputData[confIndex];
      if (confidence < 0.1) continue;
      double maxClassScore = 0.0;
      int maxClassId = -1;
      for (int j = 0; j < numClasses; j++) {
        final int scoreIndex = classesOffset + j * numBoxes + i;
        if (scoreIndex >= outputData.length) continue;
        final double classScore = outputData[scoreIndex];
        if (classScore > maxClassScore) {
          maxClassScore = classScore;
          maxClassId = j;
        }
      }
      final double finalScore = confidence * maxClassScore;
      if (finalScore < CONF_THRESHOLD) continue;
      final int hIndex = coordsOffset + 3 * numBoxes + i;
      if (hIndex >= outputData.length) continue;
      final double x = outputData[coordsOffset + 0 * numBoxes + i];
      final double y = outputData[coordsOffset + 1 * numBoxes + i];
      final double w = outputData[coordsOffset + 2 * numBoxes + i];
      final double h = outputData[hIndex];
      final double l = ((x - w / 2) * originalImageWidth).clamp(
        0.0,
        originalImageWidth.toDouble(),
      );
      final double t = ((y - h / 2) * originalImageHeight).clamp(
        0.0,
        originalImageHeight.toDouble(),
      );
      final double r = ((x + w / 2) * originalImageWidth).clamp(
        0.0,
        originalImageWidth.toDouble(),
      );
      final double b = ((y + h / 2) * originalImageHeight).clamp(
        0.0,
        originalImageHeight.toDouble(),
      );
      final double wd = math.max(0.0, r - l);
      final double ht = math.max(0.0, b - t);
      final String lbl = (maxClassId >= 0 && maxClassId < _labels.length)
          ? _labels[maxClassId]
          : 'unknown_${maxClassId}';
      final double dist =
          (originalImageHeight /
              ht.clamp(1.0, originalImageHeight.toDouble())) *
          DISTANCE_FACTOR;
      detections.add(
        Detection(
          label: lbl,
          confidence: finalScore,
          bbox: Rect.fromLTWH(l, t, wd, ht),
          distance: dist,
        ),
      );
    }
    return _nms(detections, IOU_THRESHOLD);
  }

  List<Detection> _parseDetectionsSimpleStride(
    List<List<double>> outputs,
    int imgW,
    int imgH,
  ) {
    /* ... same robust implementation ... */
    final dets = <Detection>[];
    if (outputs.isEmpty || outputs.first.isEmpty) return dets;
    final flat = outputs.first;
    const stride = 6;
    if (flat.length % stride != 0) {
      debugPrint("[TFLiteDetection] ⚠️ Fallback parse failed.");
      return [];
    }
    for (int i = 0; i + stride <= flat.length; i += stride) {
      final x = flat[i + 0];
      final y = flat[i + 1];
      final w = flat[i + 2];
      final h = flat[i + 3];
      final score = flat[i + 4];
      final cls = flat[i + 5].round();
      if (score < CONF_THRESHOLD) continue;
      final double l = ((x - w / 2) * imgW).clamp(0.0, imgW.toDouble());
      final double t = ((y - h / 2) * imgH).clamp(0.0, imgH.toDouble());
      final double r = ((x + w / 2) * imgW).clamp(0.0, imgW.toDouble());
      final double b = ((y + h / 2) * imgH).clamp(0.0, imgH.toDouble());
      final double wd = math.max(0.0, r - l);
      final double ht = math.max(0.0, b - t);
      final lbl = (cls >= 0 && cls < _labels.length)
          ? _labels[cls]
          : 'obj_$cls';
      final dist = (imgH / ht.clamp(1.0, imgH.toDouble())) * DISTANCE_FACTOR;
      dets.add(
        Detection(
          label: lbl,
          confidence: score,
          bbox: Rect.fromLTWH(l, t, wd, ht),
          distance: dist,
        ),
      );
    }
    return _nms(dets, IOU_THRESHOLD);
  }

  List<Detection> _nms(List<Detection> dets, double iouThresh) {
    /* ... same robust implementation ... */
    if (dets.isEmpty) return [];
    dets.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <Detection>[];
    final List<bool> discarded = List.filled(dets.length, false);
    for (int i = 0; i < dets.length; i++) {
      if (discarded[i]) continue;
      kept.add(dets[i]);
      for (int j = i + 1; j < dets.length; j++) {
        if (discarded[j]) continue;
        if (dets[i].label == dets[j].label &&
            _iou(dets[i].bbox, dets[j].bbox) > iouThresh) {
          discarded[j] = true;
        }
      }
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    /* ... same robust implementation ... */
    if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0)
      return 0.0;
    final il = math.max(a.left, b.left);
    final it = math.max(a.top, b.top);
    final ir = math.min(a.right, b.right);
    final ib = math.min(a.bottom, b.bottom);
    final iw = math.max(0.0, ir - il);
    final ih = math.max(0.0, ib - it);
    final areaI = iw * ih;
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final areaU = areaA + areaB - areaI;
    if (areaU <= 1e-6) return 0.0;
    return (areaI / areaU).clamp(0.0, 1.0);
  }

  Future<void> dispose() async {
    /* ... same robust implementation ... */
    debugPrint("[TFLiteDetection] ♻️ Disposing service...");
    _isInitialized = false;
    try {
      _interpreter?.close();
      _interpreter = null;
      if (!_detectionsController.isClosed) {
        await _detectionsController.close();
        debugPrint("[TFLiteDetection] Detections stream closed.");
      }
      debugPrint("[TFLiteDetection] Dispose complete.");
    } catch (e) {
      debugPrint("[TFLiteDetection] ⚠️ Dispose error: $e");
    }
  }
}
