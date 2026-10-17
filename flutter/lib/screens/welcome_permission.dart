import 'package:flutter/material.dart';

/// One-time welcome/permission screen shown on first launch.
///
/// The device owner taps "Allow Remote Access" once, after which the app
/// auto-applies the embedded operator config and connects to the webconsole.
/// No further configuration is required from the device owner.
class WelcomePermissionScreen extends StatefulWidget {
  final VoidCallback onAllow;

  const WelcomePermissionScreen({super.key, required this.onAllow});

  @override
  State<WelcomePermissionScreen> createState() => _WelcomePermissionScreenState();
}

class _WelcomePermissionScreenState extends State<WelcomePermissionScreen> {
  bool _allowScreenCapture = false;
  bool _allowRemoteControl = false;
  bool _allowBootStart = false;

  bool get _allGranted => _allowScreenCapture && _allowRemoteControl && _allowBootStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F62FE),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.devices,
                  size: 100,
                  color: Colors.white,
                ),
                const SizedBox(height: 32),
                const Text(
                  'BetterDesk Remote Access',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enable operators to securely remote-control this device.\n'
                  'You only need to do this once.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                _permissionTile(
                  icon: Icons.screen_share,
                  title: 'Share Screen',
                  subtitle: 'Operator can view your screen',
                  value: _allowScreenCapture,
                  onChanged: (v) => setState(() => _allowScreenCapture = v ?? false),
                ),
                const SizedBox(height: 16),
                _permissionTile(
                  icon: Icons.touch_app,
                  title: 'Remote Control',
                  subtitle: 'Operator can control this device',
                  value: _allowRemoteControl,
                  onChanged: (v) => setState(() => _allowRemoteControl = v ?? false),
                ),
                const SizedBox(height: 16),
                _permissionTile(
                  icon: Icons.power,
                  title: 'Start on Boot',
                  subtitle: 'Always accept operator connections',
                  value: _allowBootStart,
                  onChanged: (v) => setState(() => _allowBootStart = v ?? false),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _allGranted ? widget.onAllow : null,
                    icon: const Icon(Icons.device_hub),
                    label: const Text('Allow Remote Access'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F62FE),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (!_allGranted)
                  const Text(
                    'Please enable all permissions to continue.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? Colors.green : Colors.white24,
          width: value ? 2 : 1,
        ),
      ),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.green,
        checkColor: Colors.white,
      ),
    );
  }
}