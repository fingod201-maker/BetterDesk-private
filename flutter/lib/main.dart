import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/unattended_access.dart';
import 'screens/setup_permissions.dart';
import 'screens/remote_viewer.dart';
import 'services/setup_service.dart';

const String kBakedOperatorHost = String.fromEnvironment('OPERATOR_HOST', defaultValue: '');
const int kBakedOperatorPort = int.fromEnvironment('OPERATOR_PORT', defaultValue: 21122);
const bool kBakedUseHttps = bool.fromEnvironment('USE_HTTPS', defaultValue: false);
const String kBakedPasswordHash = String.fromEnvironment('EMBEDDED_PASSWORD_HASH', defaultValue: '');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BetterDeskClientApp());
}

class BetterDeskClientApp extends StatelessWidget {
  const BetterDeskClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zoom-private',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0753FB)),
      ),
      home: const AppRouter(),
    );
  }
}

/// Routes between the one-time setup wizard, auto-connect, and the remote
/// viewer based on persisted state.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _ready = false;

  /// Setup wizard is shown on first run, and again whenever a required grant
  /// is missing. Android drops the MediaProjection consent after a reboot or
  /// process death (it cannot be persisted), so this also routes the user
  /// straight back to the one-step re-authorization screen.
  bool _needsSetup = true;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final complete = prefs.getBool('betterdesk_setup_complete') ?? false;

    var needsSetup = !complete;
    if (complete) {
      final status = await SetupService().getStatus();
      needsSetup = !status.requiredGranted;
    }

    if (!mounted) return;
    setState(() {
      _needsSetup = needsSetup;
      _ready = true;
    });
  }

  Future<void> _markSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('betterdesk_setup_complete', true);
    if (mounted) setState(() => _needsSetup = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needsSetup) {
      return SetupPermissionsScreen(onComplete: _markSetupComplete);
    }

    if (!_isConnected) {
      return UnattendedAccessScreen(
        operatorHost: kBakedOperatorHost,
        operatorPort: kBakedOperatorPort,
        passwordHash: kBakedPasswordHash,
        useHttps: kBakedUseHttps,
        onConnected: () => setState(() => _isConnected = true),
      );
    }

    return const RemoteViewerScreen(
      deviceId: 'embedded-device',
      deviceName: 'Operator-Managed Device',
    );
  }
}

