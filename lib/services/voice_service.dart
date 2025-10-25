// Path: lib/services/voice_service.dart
// Enhanced TTS with spatial audio simulation and intelligent queuing

import 'dart:async';
import 'dart:collection';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

enum AnnouncementPriority {
  critical, // Interrupt everything
  high, // Interrupt non-urgent
  normal, // Queue normally
  low, // Can be dropped if queue is full
}

class VoiceAnnouncement {
  final String text;
  final AnnouncementPriority priority;
  final double? spatialPosition; // -1 (left) to 1 (right), null for center
  final DateTime timestamp;

  VoiceAnnouncement({
    required this.text,
    required this.priority,
    this.spatialPosition,
  }) : timestamp = DateTime.now();
}

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  final Queue<VoiceAnnouncement> _queue = Queue();
  final int _maxQueueSize = 5;

  Timer? _processingTimer;
  VoiceAnnouncement? _currentAnnouncement;

  // Voice settings
  double _baseVolume = 1.0;
  double _basePitch = 1.0;
  double _baseRate = 0.5;
  String? _preferredLanguage;

  // Statistics
  int _totalAnnouncements = 0;
  int _droppedAnnouncements = 0;

  VoiceService() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _tts.setSharedInstance(true);

      // Set up handlers
      _tts.setStartHandler(() {
        _isSpeaking = true;
        debugPrint("[VoiceService] Started speaking");
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentAnnouncement = null;
        debugPrint("[VoiceService] Completed speaking");
        _processQueue();
      });

      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        _currentAnnouncement = null;
        debugPrint("[VoiceService] TTS error: $msg");
        _processQueue();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _currentAnnouncement = null;
        debugPrint("[VoiceService] Speech cancelled");
      });

      // Configure default voice settings
      await _tts.setVolume(_baseVolume);
      await _tts.setPitch(_basePitch);
      await _tts.setSpeechRate(_baseRate);

      // Try to set a good quality voice
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setVoice({"name": "Samantha", "locale": "en-US"});
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setVoice({
          "name": "en-us-x-sfg#male_1-local",
          "locale": "en-US",
        });
      }

      _isInitialized = true;
      debugPrint("[VoiceService] ✅ Initialized successfully");

      // Start queue processor
      _startQueueProcessor();
    } catch (e, st) {
      debugPrint("[VoiceService] ⚠️ Initialization error: $e\n$st");
    }
  }

  void _startQueueProcessor() {
    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _processQueue(),
    );
  }

  void _processQueue() {
    if (!_isInitialized || _isSpeaking || _queue.isEmpty) return;

    final announcement = _queue.removeFirst();
    _speakNow(announcement);
  }

  Future<void> _speakNow(VoiceAnnouncement announcement) async {
    if (announcement.text.trim().isEmpty) return;

    _currentAnnouncement = announcement;
    _totalAnnouncements++;

    try {
      // Adjust voice parameters based on priority
      await _configureVoiceForPriority(announcement.priority);

      // Apply spatial audio effect (volume panning simulation)
      if (announcement.spatialPosition != null) {
        await _applySpatialAudio(announcement.spatialPosition!);
      }

      // Speak
      await _tts.speak(announcement.text);

      debugPrint(
        "[VoiceService] 🔊 Speaking: '${announcement.text}' "
        "(priority: ${announcement.priority.name})",
      );
    } catch (e) {
      debugPrint("[VoiceService] ⚠️ Speak error: $e");
      _isSpeaking = false;
      _currentAnnouncement = null;
    }
  }

  Future<void> _configureVoiceForPriority(AnnouncementPriority priority) async {
    switch (priority) {
      case AnnouncementPriority.critical:
        await _tts.setSpeechRate(0.85); // Slower for clarity
        await _tts.setPitch(1.4); // Higher pitch for urgency
        await _tts.setVolume(1.0); // Maximum volume
        break;

      case AnnouncementPriority.high:
        await _tts.setSpeechRate(0.75);
        await _tts.setPitch(1.2);
        await _tts.setVolume(0.95);
        break;

      case AnnouncementPriority.normal:
        await _tts.setSpeechRate(_baseRate);
        await _tts.setPitch(_basePitch);
        await _tts.setVolume(_baseVolume);
        break;

      case AnnouncementPriority.low:
        await _tts.setSpeechRate(0.45);
        await _tts.setPitch(0.9);
        await _tts.setVolume(0.8);
        break;
    }
  }

  Future<void> _applySpatialAudio(double position) async {
    // Simulate spatial audio with volume adjustment
    // Real spatial audio would require platform-specific implementation
    // position: -1 (left) to 1 (right)

    final absPosition = position.abs();
    final attenuatedVolume = _baseVolume * (1.0 - absPosition * 0.3);

    await _tts.setVolume(attenuatedVolume.clamp(0.5, 1.0));

    debugPrint(
      "[VoiceService] 🎧 Spatial audio: ${position < 0 ? 'LEFT' : 'RIGHT'} "
      "(position: ${position.toStringAsFixed(2)})",
    );
  }

  /// Main public API - speak with intelligent queuing
  void speak(String text, {bool urgent = false, double? spatialPosition}) {
    if (!_isInitialized) {
      debugPrint("[VoiceService] ⚠️ Not initialized, queueing for later");
      return;
    }

    final priority = urgent
        ? AnnouncementPriority.critical
        : AnnouncementPriority.normal;

    final announcement = VoiceAnnouncement(
      text: text,
      priority: priority,
      spatialPosition: spatialPosition,
    );

    _enqueue(announcement);
  }

  /// Announce with specific priority
  void announceWithPriority(
    String text,
    AnnouncementPriority priority, {
    double? spatialPosition,
  }) {
    if (!_isInitialized) return;

    final announcement = VoiceAnnouncement(
      text: text,
      priority: priority,
      spatialPosition: spatialPosition,
    );

    _enqueue(announcement);
  }

  void _enqueue(VoiceAnnouncement announcement) {
    // Handle critical priority - interrupt current speech
    if (announcement.priority == AnnouncementPriority.critical) {
      if (_isSpeaking) {
        _tts.stop();
      }
      _queue.clear();
      _queue.addFirst(announcement);
      _processQueue();
      return;
    }

    // Handle high priority - add to front but don't interrupt
    if (announcement.priority == AnnouncementPriority.high) {
      _queue.addFirst(announcement);
      return;
    }

    // Check queue size
    if (_queue.length >= _maxQueueSize) {
      // Try to drop low priority items first
      final lowPriorityRemoved = _queue.any((a) {
        if (a.priority == AnnouncementPriority.low) {
          _queue.remove(a);
          _droppedAnnouncements++;
          return true;
        }
        return false;
      });

      // If no low priority items, drop oldest normal priority
      if (!lowPriorityRemoved && _queue.length >= _maxQueueSize) {
        _queue.removeFirst();
        _droppedAnnouncements++;
        debugPrint("[VoiceService] ⚠️ Queue full, dropped announcement");
      }
    }

    _queue.addLast(announcement);
  }

  /// Stop current speech
  Future<void> stop() async {
    await _tts.stop();
    _queue.clear();
    _isSpeaking = false;
    _currentAnnouncement = null;
  }

  /// Pause speech (if supported)
  Future<void> pause() async {
    if (_isSpeaking) {
      await _tts.pause();
    }
  }

  /// Configure voice settings
  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0);
    if (!_isSpeaking) {
      await _tts.setVolume(_baseVolume);
    }
  }

  Future<void> setPitch(double pitch) async {
    _basePitch = pitch.clamp(0.5, 2.0);
    if (!_isSpeaking) {
      await _tts.setPitch(_basePitch);
    }
  }

  Future<void> setRate(double rate) async {
    _baseRate = rate.clamp(0.0, 1.0);
    if (!_isSpeaking) {
      await _tts.setSpeechRate(_baseRate);
    }
  }

  Future<void> setLanguage(String languageCode) async {
    _preferredLanguage = languageCode;
    await _tts.setLanguage(languageCode);
  }

  /// Get available voices
  Future<List<dynamic>> getVoices() async {
    try {
      return await _tts.getVoices ?? [];
    } catch (e) {
      debugPrint("[VoiceService] Error getting voices: $e");
      return [];
    }
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'total_announcements': _totalAnnouncements,
      'dropped_announcements': _droppedAnnouncements,
      'queue_size': _queue.length,
      'is_speaking': _isSpeaking,
      'current_text': _currentAnnouncement?.text,
    };
  }

  Future<void> dispose() async {
    _processingTimer?.cancel();
    _queue.clear();
    await _tts.stop();
    debugPrint("[VoiceService] 🔇 Disposed");
  }
}
