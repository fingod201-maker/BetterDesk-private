import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String kBakedServerHost = String.fromEnvironment('SERVER_HOST', defaultValue: '');
const bool kBakedUseHttps = bool.fromEnvironment('USE_HTTPS', defaultValue: false);
const int kListenPort = 21122;

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
      home: const UnattendedAccessScreen(),
    );
  }
}

class UnattendedAccessScreen extends StatefulWidget {
  const UnattendedAccessScreen({super.key});

  @override
  State<UnattendedAccessScreen> createState() => _UnattendedAccessScreenState();
}

class _UnattendedAccessScreenState extends State<UnattendedAccessScreen> {
  final _storage = const FlutterSecureStorage();

  String _serverHost = kBakedServerHost;
  bool _useHttps = kBakedUseHttps;
  bool _unattendedEnabled = false;
  bool _hasPassword = false;
  String _deviceId = '';
  String _appVersion = '';
  bool _loading = true;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedHost = await _storage.read(key: 'betterdesk_server_host') ??
        prefs.getString('server_host') ?? '';
    final storedUseHttps = prefs.getBool('use_https') ?? false;

    setState(() {
      _serverHost = kBakedServerHost.isNotEmpty ? kBakedServerHost : storedHost;
      _useHttps = kBakedUseHttps || storedUseHttps;
      _loading = false;
    });

    _loadDeviceInfo();
    _refreshStatus();
  }

  Future<void> _loadDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final packageInfo = await PackageInfo.fromPlatform();

    setState(() {
      _deviceId = androidInfo.id;
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _status = _unattendedEnabled
          ? 'Unattended access: ENABLED (port $kListenPort)'
          : 'Unattended access: DISABLED';
    });
  }

  String get _baseUrl {
    final scheme = _useHttps ? 'https' : 'http';
    return '$scheme://$_serverHost';
  }

  Future<void> _toggleUnattended(bool value) async {
    setState(() => _unattendedEnabled = value);
  }

  Future<void> _setPermanentPassword(String password) async {
    if (password.isNotEmpty) {
      await _storage.write(key: 'betterdesk_permanent_password', value: password);
      setState(() => _hasPassword = true);
    } else {
      await _storage.delete(key: 'betterdesk_permanent_password');
      setState(() => _hasPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('BetterDesk — Unattended Access'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.device_know_better, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              'Unattended Remote Access',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Allow operators to remotely control this device at any time.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

