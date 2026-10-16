import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/unattended_access.dart';
import 'screens/welcome_permission.dart';
import 'screens/remote_viewer.dart';

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
      title: 'BetterDesk Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F62FE)),
      ),
      home: const AppRouter(),
    );
  }
}

/// Routes between welcome, setup, and remote viewer based on state.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _hasSeenWelcome = false;
  bool _hasGrantedPermission = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasSeenWelcome = prefs.getBool('betterdesk_seen_welcome') ?? false;
      _hasGrantedPermission = prefs.getBool('betterdesk_permission_granted') ?? false;
    });
  }

  Future<void> _markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('betterdesk_seen_welcome', true);
    setState(() => _hasSeenWelcome = true);
  }

  Future<void> _markPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('betterdesk_permission_granted', true);
    setState(() => _hasGrantedPermission = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSeenWelcome) {
      return WelcomePermissionScreen(
        onAllow: () async {
          await _markWelcomeSeen();
          await _markPermissionGranted();
          setState(() => _hasGrantedPermission = true);
        },
      );
    }

    if (!_hasGrantedPermission) {
      return WelcomePermissionScreen(
        onAllow: () async {
          await _markPermissionGranted();
          setState(() => _hasGrantedPermission = true);
        },
      );
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

