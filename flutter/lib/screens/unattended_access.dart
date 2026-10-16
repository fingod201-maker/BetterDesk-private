import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/connection_service.dart';

class UnattendedAccessScreen extends StatefulWidget {
  const UnattendedAccessScreen({super.key});

  @override
  State<UnattendedAccessScreen> createState() => _UnattendedAccessScreenState();
}

class _UnattendedAccessScreenState extends State<UnattendedAccessScreen> {
  final _storage = const FlutterSecureStorage();
  final ConnectionService _conn = ConnectionService();

  String _serverHost = '';
  bool _useHttps = false;
  bool _unattendedEnabled = false;
  bool _hasPassword = false;
  bool _loading = true;
  String _status = 'Initializing...';
  String _deviceId = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedHost = await _storage.read(key: 'betterdesk_server_host') ??
        prefs.getString('server_host') ??
        '';
    final storedUseHttps = prefs.getBool('use_https') ?? false;

    final config = await _conn.getUnattendedConfig();

    setState(() {
      _serverHost = storedHost;
      _useHttps = storedUseHttps;
      _unattendedEnabled = config['enabled'] ?? false;
      _hasPassword = config['hasPassword'] ?? false;
      _loading = false;
    });

    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    setState(() {
      _deviceId = 'android-${_serverHost.hashCode}';
      _appVersion = '1.5.0+104090003';
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
      appBar: AppBar(
        title: const Text('BetterDesk — Unattended Access'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showDeviceInfoDialog(context),
          ),
        ],
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

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server Connection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _serverHost,
                      decoration: const InputDecoration(
                        labelText: 'Server host',
                        border: OutlineInputBorder(),
                        hintText: 'panel.telcom.stream',
                      ),
                      onChanged: (v) => _serverHost = v,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Use HTTPS/WSS'),
                      subtitle: const Text('Encrypt all traffic with TLS'),
                      value: _useHttps,
                      onChanged: (v) => setState(() => _useHttps = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Permanent Operator Password',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_hasPassword)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Set permanent operator password',
                        border: OutlineInputBorder(),
                        hintText: 'Minimum 8 characters',
                        helperText:
                            'Operator must enter this to gain remote control. Stored encrypted.',
                      ),
                      onChanged: (v) async {
                        if (v.isNotEmpty) {
                          await _conn.setPermanentPassword(v);
                          setState(() => _hasPassword = true);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_hasPassword)
                      TextButton.icon(
                        onPressed: () async {
                          await _conn.clearPermanentPassword();
                          setState(() => _hasPassword = false);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('Remove Password'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              title: const Text('Enable Unattended Access'),
              subtitle: const Text(
                'Device accepts incoming operator connections on boot',
              ),
              value: _unattendedEnabled,
              onChanged: (v) async {
                setState(() => _unattendedEnabled = v);
              },
              activeColor: Colors.green,
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _unattendedEnabled
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _unattendedEnabled ? Colors.green : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _unattendedEnabled
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: _unattendedEnabled ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ],
              ),
            ),
            const Spacer(),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _unattendedEnabled && _hasPassword ? null : () {},
                    icon: const Icon(Icons.devices),
                    label: const Text('Start Service'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveConfig() async {
    await _conn.saveServerConfig(
      host: _serverHost,
      useHttps: _useHttps,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved')),
      );
    }
  }

  void _showDeviceInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Device Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID: $_deviceId'),
            Text('Version: $_appVersion'),
            Text('Server: $_baseUrl'),
            const SizedBox(height: 12),
            Text(
              'Give this Device ID to the operator to connect.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _conn.dispose();
    super.dispose();
  }