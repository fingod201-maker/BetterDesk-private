import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The public host clients connect to — baked at build time via dart-define
/// and/or the `betterdesk_server_host` Android resource.
const String kBakedServerHost = bool.fromEnvironment('SERVER_HOST', defaultValue: '')
    .isNotEmpty ? const String.fromEnvironment('SERVER_HOST') : '';

/// Whether to use HTTPS/WSS — baked at build time.
const bool kBakedUseHttps = bool.fromEnvironment('USE_HTTPS', defaultValue: 'false');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BetterDeskClientApp());
}

class BetterDeskClientApp extends StatelessWidget {
  const BetterDeskClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BetterDesk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F62FE)),
      ),
      home: const ConnectionScreen(),
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  String _serverHost = '';
  bool _useHttps = false;
  bool _loading = true;

  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    // Preference order: baked-in build value > secure storage > shared prefs > empty
    final prefs = await SharedPreferences.getInstance();
    final storedHost = await _storage.read(key: 'betterdesk_server_host') ?? prefs.getString('server_host') ?? '';
    setState(() {
      _serverHost = kBakedServerHost.isNotEmpty ? kBakedServerHost : storedHost;
      _useHttps = kBakedUseHttps || prefs.getBool('use_https') ?? false;
      _loading = false;
    });
  }

  String get _baseUrl {
    final scheme = _useHttps ? 'https' : 'http';
    return '$scheme://$_serverHost';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('BetterDesk Client')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.device_know_better, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text('Server: $_baseUrl', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _serverHost.isEmpty ? null : () {},
              icon: const Icon(Icons.connect_without_contact),
              label: const Text('Connect'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.settings),
              label: const Text('Configure Server'),
            ),
          ],
        ),
      ),
    );
  }
}
