// Path: lib/screens/settings_screen.dart
// Professional Settings Screen with Accessibility Options

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Settings State (In production, use SharedPreferences or similar)
  double _voiceVolume = 0.8;
  double _voiceSpeed = 1.0;
  double _detectionSensitivity = 0.7;
  bool _hapticFeedback = true;
  bool _continuousNarration = false;
  bool _urgentAlertsOnly = false;
  String _selectedVoice = 'Default';
  double _personalSpace = 2.0; // meters

  final List<String> _voices = ['Default', 'Male', 'Female', 'High Contrast'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Voice Settings Section
          _buildSectionHeader('Voice & Audio'),
          _buildSettingsCard([
            _buildSliderSetting(
              icon: Icons.volume_up,
              label: 'Voice Volume',
              value: _voiceVolume,
              min: 0.0,
              max: 1.0,
              onChanged: (val) => setState(() => _voiceVolume = val),
              displayValue: '${(_voiceVolume * 100).toInt()}%',
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildSliderSetting(
              icon: Icons.speed,
              label: 'Voice Speed',
              value: _voiceSpeed,
              min: 0.5,
              max: 2.0,
              onChanged: (val) => setState(() => _voiceSpeed = val),
              displayValue: '${_voiceSpeed.toStringAsFixed(1)}x',
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildDropdownSetting(
              icon: Icons.record_voice_over,
              label: 'Voice Type',
              value: _selectedVoice,
              items: _voices,
              onChanged: (val) => setState(() => _selectedVoice = val!),
            ),
          ]),

          const SizedBox(height: 24),

          // Detection Settings Section
          _buildSectionHeader('Detection & Alerts'),
          _buildSettingsCard([
            _buildSliderSetting(
              icon: Icons.tune,
              label: 'Detection Sensitivity',
              value: _detectionSensitivity,
              min: 0.3,
              max: 1.0,
              onChanged: (val) => setState(() => _detectionSensitivity = val),
              displayValue: _detectionSensitivity >= 0.8
                  ? 'High'
                  : _detectionSensitivity >= 0.6
                  ? 'Medium'
                  : 'Low',
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildSliderSetting(
              icon: Icons.social_distance,
              label: 'Personal Space Alert',
              value: _personalSpace,
              min: 0.5,
              max: 5.0,
              onChanged: (val) => setState(() => _personalSpace = val),
              displayValue: '${_personalSpace.toStringAsFixed(1)}m',
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildSwitchSetting(
              icon: Icons.priority_high,
              label: 'Urgent Alerts Only',
              subtitle: 'Only announce high-priority obstacles',
              value: _urgentAlertsOnly,
              onChanged: (val) => setState(() => _urgentAlertsOnly = val),
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildSwitchSetting(
              icon: Icons.mic,
              label: 'Continuous Narration',
              subtitle: 'Provide ongoing environment description',
              value: _continuousNarration,
              onChanged: (val) => setState(() => _continuousNarration = val),
            ),
          ]),

          const SizedBox(height: 24),

          // Feedback Settings Section
          _buildSectionHeader('Feedback & Interaction'),
          _buildSettingsCard([
            _buildSwitchSetting(
              icon: Icons.vibration,
              label: 'Haptic Feedback',
              subtitle: 'Vibration alerts for obstacles',
              value: _hapticFeedback,
              onChanged: (val) => setState(() => _hapticFeedback = val),
            ),
          ]),

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader('About'),
          _buildSettingsCard([
            _buildActionTile(
              icon: Icons.help_outline,
              label: 'Tutorial',
              onTap: () {
                // Navigate to tutorial
                HapticFeedback.lightImpact();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildActionTile(
              icon: Icons.bug_report_outlined,
              label: 'Report Issue',
              onTap: () {
                // Report issue
                HapticFeedback.lightImpact();
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            _buildActionTile(
              icon: Icons.info_outline,
              label: 'About Calm Co-Pilot',
              onTap: () {
                _showAboutDialog();
              },
            ),
          ]),

          const SizedBox(height: 24),

          // Version Info
          Center(
            child: Text(
              'Version 1.0.0 (Hackathon Build)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.teal.shade300,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.teal.shade300.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSliderSetting({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String displayValue,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.teal.shade300, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: Colors.teal.shade300,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.teal.shade300,
              inactiveTrackColor: Colors.grey.shade800,
              thumbColor: Colors.teal.shade300,
              overlayColor: Colors.teal.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchSetting({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: Colors.teal.shade300, size: 24),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      ),
      trailing: Switch(
        value: value,
        onChanged: (val) {
          HapticFeedback.lightImpact();
          onChanged(val);
        },
        activeColor: Colors.teal.shade300,
        activeTrackColor: Colors.teal.withOpacity(0.5),
      ),
    );
  }

  Widget _buildDropdownSetting({
    required IconData icon,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.teal.shade300, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade300.withOpacity(0.3)),
            ),
            child: DropdownButton<String>(
              value: value,
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    style: TextStyle(color: Colors.teal.shade300),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                HapticFeedback.lightImpact();
                onChanged(val);
              },
              underline: const SizedBox(),
              dropdownColor: Colors.grey.shade900,
              icon: Icon(Icons.arrow_drop_down, color: Colors.teal.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: Colors.teal.shade300, size: 24),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: Colors.grey.shade600,
        size: 16,
      ),
      onTap: onTap,
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.teal.shade300.withOpacity(0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.remove_red_eye_outlined, color: Colors.teal.shade300),
            const SizedBox(width: 12),
            const Text('Calm Co-Pilot', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI-Powered Vision Assistant',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Calm Co-Pilot uses advanced AI and computer vision to help visually impaired individuals navigate complex environments safely and independently.',
              style: TextStyle(
                color: Colors.grey.shade300,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Features:',
              style: TextStyle(
                color: Colors.teal.shade300,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildFeatureItem('Real-time object detection'),
            _buildFeatureItem('3D spatial awareness'),
            _buildFeatureItem('Intelligent priority engine'),
            _buildFeatureItem('Context-aware audio feedback'),
            _buildFeatureItem('Adaptive navigation guidance'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CLOSE',
              style: TextStyle(
                color: Colors.teal.shade300,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.teal.shade300, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
