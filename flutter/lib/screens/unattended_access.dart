import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/connection_service.dart';

class UnattendedAccessScreen extends StatefulWidget {
  final String operatorHost;
  final int operatorPort;
  final String passwordHash;
  final bool useHttps;
  final VoidCallback onConnected;

  const UnattendedAccessScreen({
    super.key,
    required this.operatorHost,
    required this.operatorPort,
    required this.passwordHash,
    required this.useHttps,
    required this.onConnected,
  });

  @override
  State<UnattendedAccessScreen> createState() => _UnattendedAccessScreenState();
}

class _UnattendedAccessScreenState extends State<UnattendedAccessScreen> {
  final _storage = const FlutterSecureStorage();
  final ConnectionService _conn = ConnectionService();

  bool _applyingConfig = false;
  bool _configApplied = false;
  bool _connecting = false;
  bool _connected = false;
  String _status = 'Ready to connect';
  String _deviceId = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _deviceId = 'android-${widget.operatorHost.hashCode}';
      _appVersion = '1.5.0+104090003';
    });
    _applyEmbeddedConfig();
  }

  Future<void> _applyEmbeddedConfig() async {
    setState(() {
      _applyingConfig = true;
      _status = 'Applying operator configuration...';
    });

    await _conn.applyEmbeddedConfig(
      host: widget.operatorHost,
      port: widget.operatorPort,
      passwordHash: widget.passwordHash,
    );

    await _conn.saveServerConfig(
      host: widget.operatorHost,
      useHttps: widget.useHttps,
    );

    setState(() {
      _applyingConfig = false;
      _configApplied = true;
      _status = 'Configuration applied. Connecting to operator...';
    });

    await Future.delayed(const Duration(seconds: 1));
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    setState(() {
      _connecting = true;
      _status = 'Connecting to ${widget.operatorHost}:${widget.operatorPort}...';
    });

    final success = await _conn.autoConnectToOperator();


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BetterDesk — Auto-Connect'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.device_hub, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              'Operator-Managed Device',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This device is pre-configured for remote management.\n'
                  'No setup required — just allow access once.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Embedded Configuration',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Operator: ${widget.operatorHost}'),
                    Text('Port: ${widget.operatorPort}'),
                    Text(
                      'Protocol: ${widget.useHttps ? 'HTTPS/WSS' : 'HTTP/WS'}',
                    ),
                    Text(
                      'Password: ${widget.passwordHash.isNotEmpty ? 'Configured (PBKDF2 hashed)' : 'Not set'}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Device ID: $_deviceId',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _connected
                    ? Colors.green.shade50
                    : _connecting
                        ? Colors.blue.shade50
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _connected
                      ? Colors.green
                      : _connecting
                          ? Colors.blue
                          : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  if (_connecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _connected ? Icons.check_circle : Icons.info,
                      color: _connected ? Colors.green : Colors.blue,
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ],
              ),
            ),
            const Spacer(),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device Information',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('ID: $_deviceId', style: const TextStyle(fontSize: 12)),
                  Text('Version: $_appVersion', style: const TextStyle(fontSize: 12)),
                  Text('Operator URL: $_baseUrl', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _conn.dispose();
    super.dispose();
  }
}
    setState(() {
      _connecting = false;
      _connected = success;
      _status = success
          ? 'Connected to operator webconsole'
          : 'Connection failed - will retry';
    });

    if (success && mounted) {
      widget.onConnected();
    }
  }

  String get _baseUrl {
    final scheme = widget.useHttps ? 'https' : 'http';
    return '$scheme://${widget.operatorHost}:${widget.operatorPort}';
  }