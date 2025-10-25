// Path: lib/screens/main_screen.dart
// Professional Hackathon-Ready Main Screen with Enhanced UI/UX

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../services/detection_service_tflite.dart';
import '../services/voice_service.dart';
import '../services/sensor_service.dart';
import '../core/priority_engine.dart';
import '../widgets/detection_painter.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Services
  final CameraService _cameraService = CameraService();
  final SensorService _sensorService = SensorService();
  final VoiceService _voiceService = VoiceService();
  late final PriorityEngine _priorityEngine;
  DetectionServiceTFLite? _detectionService;

  // State
  List<Detection> _latestDetections = [];
  SelectedEvent? _currentEvent;
  CameraDescription? _cameraDesc;
  Size _imageSize = Size.zero;
  Size _screenSize = Size.zero;

  // UI State
  bool _isInitializing = true;
  bool _isActive = true;
  String _statusMessage = "Initializing...";
  int _detectionCount = 0;
  double _fps = 0.0;
  DateTime _lastFrameTime = DateTime.now();

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Subscriptions
  StreamSubscription<List<Detection>>? _detSub;
  StreamSubscription<SelectedEvent?>? _selSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priorityEngine = PriorityEngine(sensorService: _sensorService);

    // Setup pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    // Check if first launch - show onboarding
    // For now, directly start
    await _startAll();
  }

  Future<void> _startAll() async {
    setState(() {
      _isInitializing = true;
      _statusMessage = "Starting camera...";
    });

    try {
      // Initialize camera
      _cameraDesc = await _cameraService.initialize();
      final controller = _cameraService.controller;

      if (controller != null) {
        final ps = controller.value.previewSize;
        if (ps != null) {
          _imageSize = Size(ps.width, ps.height);
        }
      }

      setState(() => _statusMessage = "Initializing sensors...");
      await _sensorService.initialize();

      setState(() => _statusMessage = "Loading AI model...");
      _detectionService = DetectionServiceTFLite(
        cameraStream: _cameraService.imageStream,
        frameSkip: 3,
      );

      // Wire detection stream
      _detSub = _detectionService!.detectionsStream.listen((detections) {
        if (!mounted) return;

        // Calculate FPS
        final now = DateTime.now();
        final diff = now.difference(_lastFrameTime).inMilliseconds;
        if (diff > 0) {
          _fps = 1000.0 / diff;
        }
        _lastFrameTime = now;

        setState(() {
          _latestDetections = detections;
          _detectionCount = detections.length;
        });

        if (_isActive) {
          _priorityEngine.processDetections(
            detections,
            _imageSize.width,
            userSpeed: _sensorService.isMoving ? 1.0 : 0.0,
          );
        }
      });

      // Wire priority engine stream
      _selSub = _priorityEngine.selectedStream.listen((selected) {
        if (!mounted || !_isActive) return;

        setState(() => _currentEvent = selected);

        if (selected != null) {
          final text = _formatAnnouncement(
            selected.detection,
            selected.urgency,
          );
          final urgent = selected.urgency >= 0.85;
          _voiceService.speak(text, urgent: urgent);

          // Haptic feedback for urgent events
          if (urgent) {
            HapticFeedback.heavyImpact();
          } else if (selected.urgency >= 0.6) {
            HapticFeedback.mediumImpact();
          }
        } else {
          if (_sensorService.isMoving && _latestDetections.isEmpty) {
            _voiceService.speak("Path clear.", urgent: false);
          }
        }
      });

      setState(() {
        _isInitializing = false;
        _statusMessage = "Active";
      });
    } catch (e, st) {
      debugPrint("[MainScreen] Startup error: $e\n$st");
      setState(() {
        _isInitializing = false;
        _statusMessage = "Error: ${e.toString()}";
      });
    }
  }

  String _formatAnnouncement(Detection d, double urgency) {
    final centerX = d.bbox.left + d.bbox.width / 2.0;
    final side = centerX < (_imageSize.width / 2.0) ? "left" : "right";
    final distStr = d.distance != null
        ? "${d.distance!.toStringAsFixed(1)} meters"
        : "nearby";

    if (urgency >= 0.85) {
      return "STOP! ${d.label} directly ahead, $distStr.";
    } else if (urgency >= 0.6) {
      return "Caution. ${d.label} approaching from the $side, $distStr.";
    } else {
      return "${d.label} detected on the $side, $distStr away.";
    }
  }

  void _toggleActive() {
    setState(() {
      _isActive = !_isActive;
      _statusMessage = _isActive ? "Active" : "Paused";
    });

    if (_isActive) {
      _voiceService.speak("Navigation assistance resumed.", urgent: false);
    } else {
      _voiceService.speak("Navigation assistance paused.", urgent: false);
    }

    HapticFeedback.mediumImpact();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _cameraService.stopStream();
    }
    if (state == AppLifecycleState.resumed && _cameraDesc != null) {
      _startAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detSub?.cancel();
    _selSub?.cancel();
    _cameraService.dispose();
    _detectionService?.dispose();
    _sensorService.dispose();
    _voiceService.dispose();
    _priorityEngine.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraService.controller;
    _screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitializing
          ? _buildLoadingScreen()
          : _buildMainContent(controller),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.teal.shade900, Colors.black],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Logo
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.teal.shade300, Colors.teal.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.5),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // App Name
            const Text(
              "Calm Co-Pilot",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "AI-Powered Vision Assistant",
              style: TextStyle(
                fontSize: 16,
                color: Colors.teal.shade300,
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 60),

            // Loading Indicator
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade300),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              _statusMessage,
              style: TextStyle(fontSize: 16, color: Colors.teal.shade200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera Preview Layer
        _buildCameraPreview(controller),

        // Detection Overlay Layer
        _buildDetectionOverlay(),

        // Gradient Overlays for Better Contrast
        _buildGradientOverlays(),

        // UI Layer
        SafeArea(
          child: Column(
            children: [_buildTopBar(), const Spacer(), _buildBottomPanel()],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview(CameraController controller) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    return Positioned.fill(
      child: CustomPaint(
        painter: DetectionPainter(
          detections: _latestDetections,
          imageSize: _imageSize,
          screenSize: _screenSize,
          // Remove or replace with the correct parameter if applicable
          boxColor: _currentEvent == null ? Colors.teal : Colors.red,
        ),
      ),
    );
  }

  Widget _buildGradientOverlays() {
    return Stack(
      children: [
        // Top gradient
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 200,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
          ),
        ),
        // Bottom gradient
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 250,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.8), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Status Indicator
          _buildStatusChip(),
          const Spacer(),
          // Settings Button
          _buildIconButton(
            icon: Icons.settings_outlined,
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final isCalm = _currentEvent == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isCalm
            ? Colors.teal.withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCalm ? Colors.teal.shade300 : Colors.red.shade300,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCalm ? Colors.teal.shade300 : Colors.red.shade300,
              boxShadow: [
                BoxShadow(
                  color: (isCalm ? Colors.teal : Colors.red).withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isCalm ? "CLEAR PATH" : "ALERT",
            style: TextStyle(
              color: isCalm ? Colors.teal.shade300 : Colors.red.shade300,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.5),
        border: Border.all(
          color: Colors.teal.shade300.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.teal.shade300),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.teal.shade300.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current Event Display
          _buildCurrentEventDisplay(),

          const SizedBox(height: 20),

          // Stats Row
          _buildStatsRow(),

          const SizedBox(height: 20),

          // Control Button
          _buildControlButton(),
        ],
      ),
    );
  }

  Widget _buildCurrentEventDisplay() {
    if (_currentEvent == null) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.teal.shade300,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "No obstacles detected",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    final urgencyPercent = (_currentEvent!.urgency * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade300,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _currentEvent!.detection.label.toUpperCase(),
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Urgency Bar
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Urgency Level",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                Text(
                  "$urgencyPercent%",
                  style: TextStyle(
                    color: Colors.red.shade300,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _currentEvent!.urgency,
                minHeight: 6,
                backgroundColor: Colors.grey.shade800,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _currentEvent!.urgency >= 0.85
                      ? Colors.red
                      : _currentEvent!.urgency >= 0.6
                      ? Colors.orange
                      : Colors.yellow,
                ),
              ),
            ),
          ],
        ),

        if (_currentEvent!.detection.distance != null) ...[
          const SizedBox(height: 8),
          Text(
            "Distance: ${_currentEvent!.detection.distance!.toStringAsFixed(1)}m",
            style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          icon: Icons.visibility_outlined,
          label: "Objects",
          value: "$_detectionCount",
        ),
        _buildStatItem(
          icon: Icons.speed,
          label: "FPS",
          value: _fps.toStringAsFixed(0),
        ),
        _buildStatItem(
          icon: Icons.directions_walk,
          label: "Motion",
          value: _sensorService.isMoving ? "Moving" : "Still",
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.teal.shade300, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildControlButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleActive,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isActive
                  ? [Colors.red.shade600, Colors.red.shade800]
                  : [Colors.teal.shade600, Colors.teal.shade800],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (_isActive ? Colors.red : Colors.teal).withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isActive
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                _isActive ? "PAUSE NAVIGATION" : "RESUME NAVIGATION",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
