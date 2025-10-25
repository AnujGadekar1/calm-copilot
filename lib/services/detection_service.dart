// // File: lib/services/detection_service.dart
// // (ML Kit Version)

// import 'dart:async';
// import 'dart:io'; // For Platform check
// import 'dart:typed_data'; // For WriteBuffer
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart'; // For Rect/Size
// import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
// import 'package:google_mlkit_commons/google_mlkit_commons.dart'; // For InputImage

// /// Represents a single object detection (compatible structure).
// class Detection {
//   final String label;
//   final double confidence; // 0.0 to 1.0
//   final Rect
//   bbox; // Bounding box in InputImage coordinates (before rotation/scaling)
//   final double? distance; // Estimated distance in meters
//   // Add trackingId if needed from DetectedObject
//   final int? trackingId;

//   Detection({
//     required this.label,
//     required this.confidence,
//     required this.bbox,
//     this.distance,
//     this.trackingId,
//   });

//   @override
//   String toString() {
//     return 'Detection(label: $label, conf: ${(confidence * 100).toStringAsFixed(1)}%, '
//         'bbox: [${bbox.left.toStringAsFixed(0)}, ${bbox.top.toStringAsFixed(0)}, '
//         '${bbox.width.toStringAsFixed(0)}, ${bbox.height.toStringAsFixed(0)}], '
//         'dist: ${distance?.toStringAsFixed(2)}m)';
//   }
// }

// /// Service for running Google ML Kit object detection on a camera stream.
// class DetectionService {
//   final Stream<CameraImage> cameraStream;
//   final int frameSkip; // Process every N+1 frames

//   // Output stream for detections
//   final StreamController<List<Detection>> _detectionsController =
//       StreamController.broadcast();
//   Stream<List<Detection>> get detectionsStream => _detectionsController.stream;

//   // State Management
//   bool _isProcessing = false;
//   int _frameCount = 0;
//   bool _isInitialized = false;
//   ObjectDetector? _objectDetector; // Nullable until initialized

//   // --- Configuration ---
//   // Distance estimation factor (tune this)
//   static const double DISTANCE_FACTOR = 0.40; // Adjusted factor for ML Kit

//   DetectionService({
//     required this.cameraStream,
//     this.frameSkip =
//         2, // Default: process every 3rd frame (ML Kit can be slower)
//   }) {
//     _initialize();
//     cameraStream.listen(
//       _onCameraImage,
//       onError: (e) {
//         debugPrint("[MLKitDetection] ⚠️ Camera stream error: $e");
//       },
//       cancelOnError: false,
//     );
//   }

//   /// Initializes the ML Kit Object Detector.
//   Future<void> _initialize() async {
//     debugPrint("[MLKitDetection] Initializing...");
//     try {
//       // Use the default base model provided by ML Kit
//       final mode = DetectionMode.stream; // Use stream mode for camera feed
//       final options = ObjectDetectorOptions(
//         mode: mode,
//         classifyObjects: true, // Get labels
//         multipleObjects: true,
//       ); // Detect multiple items
//       _objectDetector = ObjectDetector(options: options);

//       _isInitialized = true;
//       debugPrint("[MLKitDetection] ✅ Initialization Complete.");
//     } catch (e, st) {
//       debugPrint("[MLKitDetection] ❌ Initialization failed: $e\n$st");
//       _objectDetector = null; // Ensure null on failure
//       _isInitialized = false;
//     }
//   }

//   /// Callback function for processing each camera image frame.
//   void _onCameraImage(CameraImage image) async {
//     _frameCount++;
//     // Skip processing if not initialized, already processing, or frame skipping
//     if (!_isInitialized || _objectDetector == null || _isProcessing) return;
//     if (_frameCount % (frameSkip + 1) != 0) return;

//     _isProcessing = true; // Acquire lock
//     final Stopwatch stopwatch = Stopwatch()..start();

//     try {
//       // --- Prepare InputImage ---
//       // We need camera description for rotation - assume it's passed or stored
//       // For simplicity, let's assume rotation is 90 for now, replace with dynamic later
//       final inputImage = _convertCameraImageToInputImage(
//         image,
//         rotationDegrees: 90,
//       );
//       if (inputImage == null) {
//         throw Exception("InputImage conversion failed.");
//       }
//       final preprocessTime = stopwatch.elapsedMilliseconds;

//       // --- Inference ---
//       stopwatch.reset();
//       final List<DetectedObject> objects = await _objectDetector!.processImage(
//         inputImage,
//       );
//       final inferenceTime = stopwatch.elapsedMilliseconds;

//       // --- Postprocessing (Convert DetectedObject to our Detection class) ---
//       stopwatch.reset();
//       final List<Detection> detections = _parseDetections(
//         objects,
//         inputImage
//             .metadata!
//             .size
//             .height, // Use height for distance heuristic in portrait
//       );
//       final postprocessTime = stopwatch.elapsedMilliseconds;

//       // --- Emit Results ---
//       if (!_detectionsController.isClosed) {
//         _detectionsController.add(detections);
//       }

//       // Optional Timing Logs
//       if (_frameCount % 30 == 0) {
//         debugPrint(
//           "[MLKitDetection Timing] Preprocess: ${preprocessTime}ms, Inference: ${inferenceTime}ms, Postprocess: ${postprocessTime}ms (#Obj: ${detections.length})",
//         );
//       }
//     } catch (e, st) {
//       debugPrint("[MLKitDetection] ⚠️ Frame processing error: $e\n$st");
//     } finally {
//       _isProcessing = false; // Release lock reliably
//       stopwatch.stop();
//     }
//   }

//   /// Converts CameraImage to ML Kit's InputImage format.
//   InputImage? _convertCameraImageToInputImage(
//     CameraImage image, {
//     required int rotationDegrees,
//   }) {
//     final formatGroup = image.format.group;
//     // Use image dimensions directly
//     final Size imageSize = Size(
//       image.width.toDouble(),
//       image.height.toDouble(),
//     );
//     // Convert rotation degrees to InputImageRotation enum
//     final InputImageRotation imageRotation =
//         InputImageRotationValue.fromRawValue(rotationDegrees) ??
//         InputImageRotation.rotation0deg;

//     // Determine the InputImageFormat based on the CameraImage format group
//     InputImageFormat? inputImageFormat;
//     if (Platform.isAndroid) {
//       // Android typically uses YUV_420_888 or NV21
//       inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
//       // Fallback if raw value is unknown
//       if (inputImageFormat == null ||
//           inputImageFormat == InputImageFormat.unknown) {
//         debugPrint(
//           "[MLKitDetection] ⚠️ Unknown Android format raw: ${image.format.raw}, defaulting to nv21.",
//         );
//         inputImageFormat = InputImageFormat.nv21; // Common default
//       }
//     } else if (Platform.isIOS) {
//       // iOS typically uses BGRA8888
//       inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
//       if (inputImageFormat == null ||
//           inputImageFormat == InputImageFormat.unknown) {
//         debugPrint(
//           "[MLKitDetection] ⚠️ Unknown iOS format raw: ${image.format.raw}, defaulting to bgra8888.",
//         );
//         inputImageFormat = InputImageFormat.bgra8888;
//       }
//     } else {
//       return null; // Unsupported platform
//     }

//     // --- Create Plane Metadata ---
//     final List<InputImagePlaneMetadata> planeData = image.planes.map((
//       Plane plane,
//     ) {
//       return InputImagePlaneMetadata(
//         bytesPerRow: plane.bytesPerRow,
//         height: plane.height,
//         width: plane.width,
//       );
//     }).toList();

//     // --- Get Image Bytes ---
//     // Needs careful handling based on format
//     Uint8List? imageBytes;
//     if (inputImageFormat == InputImageFormat.nv21) {
//       // For YUV/NV21, concatenate Y, U, V planes (or Y, VU planes)
//       // ML Kit expects NV21: Y plane followed by interleaved VU plane
//       if (image.planes.length >= 3) {
//         imageBytes = _concatenatePlanesNV21(image.planes);
//       } else {
//         debugPrint(
//           "[MLKitDetection] ⚠️ YUV format selected but < 3 planes found.",
//         );
//         return null;
//       }
//     } else if (inputImageFormat == InputImageFormat.bgra8888) {
//       // For BGRA, use the first plane's bytes directly
//       imageBytes = image.planes[0].bytes;
//     } else {
//       debugPrint(
//         "[MLKitDetection] ⚠️ Unsupported InputImageFormat: $inputImageFormat",
//       );
//       return null;
//     }

//     if (imageBytes == null) return null;

//     // --- Create InputImageMetadata ---
//     final inputImageData = InputImageMetadata(
//       size: imageSize,
//       rotation: imageRotation,
//       format: inputImageFormat,
//       bytesPerRow:
//           planeData.first.bytesPerRow, // Use Y plane's bytesPerRow typically
//     );

//     // --- Create InputImage ---
//     return InputImage.fromBytes(bytes: imageBytes, metadata: inputImageData);
//   }

//   /// Concatenates Y, U, V planes into NV21 format (Y plane + interleaved VU plane).
//   /// Assumes YUV420 planar format from CameraImage.
//   Uint8List _concatenatePlanesNV21(List<Plane> planes) {
//     final WriteBuffer allBytes = WriteBuffer();
//     // Add Y plane bytes
//     allBytes.putUint8List(planes[0].bytes);

//     // Add interleaved VU bytes
//     final Plane uPlane = planes[1];
//     final Plane vPlane = planes[2];
//     final int chromaWidth = (planes[0].width! / 2).ceil(); // Width of U/V plane
//     final int chromaHeight = (planes[0].height! / 2)
//         .ceil(); // Height of U/V plane

//     // Ensure bytesPerPixel is not null, default to 1 if it is
//     final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
//     final int uvRowStride = uPlane.bytesPerRow;

//     // Interleave U and V planes (assuming V comes first in NV21)
//     for (int row = 0; row < chromaHeight; row++) {
//       for (int col = 0; col < chromaWidth; col++) {
//         final int vuIndex = row * uvRowStride + col * uvPixelStride;
//         // Add V byte (check bounds)
//         if (vuIndex < vPlane.bytes.length) {
//           allBytes.putUint8(vPlane.bytes[vuIndex]);
//         } else {
//           allBytes.putUint8(0); // Pad if necessary
//         }
//         // Add U byte (check bounds)
//         if (vuIndex < uPlane.bytes.length) {
//           allBytes.putUint8(uPlane.bytes[vuIndex]);
//         } else {
//           allBytes.putUint8(0); // Pad if necessary
//         }
//       }
//     }
//     return allBytes.done().buffer.asUint8List();
//   }

//   /// Converts ML Kit `DetectedObject` list to our `Detection` list.
//   List<Detection> _parseDetections(
//     List<DetectedObject> objects,
//     double imageHeight,
//   ) {
//     if (objects.isEmpty) return [];

//     final List<Detection> detections = [];
//     for (final DetectedObject obj in objects) {
//       // Get the primary label and confidence
//       final String label = obj.labels.isNotEmpty
//           ? obj.labels.first.text
//           : 'unknown';
//       final double confidence = obj.labels.isNotEmpty
//           ? obj.labels.first.confidence
//           : 0.0;

//       // Filter based on confidence here if desired (e.g., if confidence < 0.3 continue;)
//       if (confidence < 0.3) continue; // Basic confidence filter

//       // Bounding box provided by ML Kit
//       final Rect bbox = obj.boundingBox;

//       // Estimate distance based on bounding box height relative to image height
//       final double boxHeight = bbox.height.clamp(
//         1.0,
//         imageHeight,
//       ); // Ensure non-zero height
//       final double distance = (imageHeight / boxHeight) * DISTANCE_FACTOR;

//       detections.add(
//         Detection(
//           label: label,
//           confidence: confidence,
//           bbox: bbox,
//           distance: distance,
//           trackingId: obj.trackingId, // Include tracking ID if available
//         ),
//       );
//     }
//     // Note: ML Kit's stream mode often implies some level of internal NMS or tracking.
//     // Explicit NMS might still be beneficial if results are noisy.
//     // return _nms(detections, IOU_THRESHOLD); // Optional: Apply NMS if needed
//     return detections;
//   }

//   /// Dispose resources.
//   Future<void> dispose() async {
//     debugPrint("[MLKitDetection] ♻️ Disposing service...");
//     _isInitialized = false;
//     try {
//       await _objectDetector?.close(); // Close the detector
//       _objectDetector = null;
//       if (!_detectionsController.isClosed) {
//         await _detectionsController.close();
//         debugPrint("[MLKitDetection] Detections stream closed.");
//       }
//       debugPrint("[MLKitDetection] Dispose complete.");
//     } catch (e) {
//       debugPrint("[MLKitDetection] ⚠️ Dispose error: $e");
//     }
//   }
// }
