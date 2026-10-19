import 'package:flutter/material.dart';
import '../services/setup_service.dart';

/// One-time RustDesk-style unattended-access setup wizard.
///
/// The device owner is prompted exactly once (during installation/first run):
///   1. Notifications          – foreground service notice (Android 13+)
///   2. Screen Share           – ONE system "Allow once / Start now" dialog;
///                               the grant is held by the service afterwards
///   3. Remote Control         – Accessibility service (deep-link to Settings)
///   4. Start on Boot          – battery-optimization exemption
///
/// After all required grants the device auto-connects to the operator
/// webconsole; no further configuration is ever required.
class SetupPermissionsScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupPermissionsScreen({super.key, required this.onComplete});

  @override
  State<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends State<SetupPermissionsScreen>
    with WidgetsBindingObserver {
  final SetupService _setup = SetupService();
  SetupStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User returned from Settings / a system dialog — re-check grants.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await _setup.getStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run(Future<SetupStatus> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await action();
      if (mounted) setState(() => _status = s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      backgroundColor: const Color(0xFF0753FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Icon(Icons.devices, size: 72, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Unattended Access Setup',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Allow the permissions below once — this is the only\n'
                      'setup this device will ever need.',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _step(
                  n: 1, icon: Icons.notifications_none,
                  title: 'Notifications',
                  subtitle: 'Shows the persistent "Remote control active" notice',
                  granted: s?.notifications,
                  button: 'Allow',
                  onPressed: () => _run(_setup.requestNotificationPermission),
                ),
                _step(
                  n: 2, icon: Icons.screen_share_outlined,
                  title: 'Screen Share',
                  subtitle: 'One system prompt ("Allow once").\n'
                      'Held by the service for this session. Android asks again\n'
                      'after every reboot — tap Allow once each time.',
                  granted: s?.screenCapture,
                  button: 'Allow once',
                  onPressed: () => _run(_setup.requestScreenCapture),
                ),
                _step(
                  n: 3, icon: Icons.touch_app_outlined,
                  title: 'Remote Control',
                  subtitle: 'Enable "BetterDesk Remote Control" in the\n'
                      'Accessibility settings list, then come back',
                  granted: s?.accessibility,
                  button: 'Open Settings',
                  onPressed: () => _run(_setup.openAccessibilitySettings),
                  hint: (s?.restrictedSettingsRequired ?? false)
                      ? 'Android blocked the toggle. On the app info page use\n'
                          '⋮ → "Allow restricted settings", then enable Accessibility.'
                      : null,
                  secondaryLabel: (s?.restrictedSettingsRequired ?? false)
                      ? 'Allow restricted settings'
                      : null,
                  onSecondary: () => _run(_setup.openAppDetailsSettings),
                ),
                _step(
                  n: 4, icon: Icons.power_settings_new,
                  title: 'Start on Boot',
                  subtitle: 'Whitelist from battery optimization so the\n'
                      'service survives Doze and restarts after reboot',
                  granted: s?.batteryExempt,
                  button: 'Allow',
                  onPressed: () => _run(_setup.requestBatteryExemption),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton.icon(
                    onPressed: (s?.requiredGranted ?? false) && !_busy
                        ? widget.onComplete
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Finish — Connect Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0753FB),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _busy ? 'Waiting for system…'
                      : (s?.requiredGranted ?? false)
                          ? 'All set — finish to connect to your operator.'
                          : 'Complete the required steps to continue.',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step({
    required int n, required IconData icon, required String title,
    required String subtitle, required bool? granted,
    required String button, required VoidCallback onPressed,
    String? hint, String? secondaryLabel, VoidCallback? onSecondary,
  }) {
    final done = granted == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done ? Colors.green : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: done ? Colors.green.shade50 : const Color(0xFFE8EEFF),
            child: done
                ? const Icon(Icons.check, color: Colors.green)
                : Icon(icon, color: const Color(0xFF0753FB)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$n. $title',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hint,
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                    ),
                  ),
                if (secondaryLabel != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : onSecondary,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        secondaryLabel,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!done)
            TextButton(onPressed: _busy ? null : onPressed, child: Text(button)),
        ],
      ),
    );
  }
}
