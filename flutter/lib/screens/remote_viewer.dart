import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class RemoteViewerScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const RemoteViewerScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<RemoteViewerScreen> createState() => _RemoteViewerScreenState();
}

class _RemoteViewerScreenState extends State<RemoteViewerScreen> {
  final ConnectionService _conn = ConnectionService();

  bool _isConnected = false;
  int _latencyMs = 0;
  bool _frameAvailable = false;
  String _connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _conn.eventStream.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.type) {
          case RemoteEventType.statusChanged:
            _isConnected = event.data['status'] == 'connected';
            _connectionStatus = event.data['status'] ?? 'disconnected';
            break;
          case RemoteEventType.latencyUpdated:
            _latencyMs = event.data['latencyMs'] ?? 0;
            break;
          case RemoteEventType.frameReady:
            _frameAvailable = true;
            break;
          default:
            break;
        }
      });
    });

    await _conn.getUnattendedConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isConnected ? Icons.link : Icons.link_off,
              color: _isConnected ? Colors.green : Colors.grey,
            ),
            onPressed: _isConnected ? _disconnect : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: _isConnected ? Colors.green.shade50 : Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle,
                  color: _isConnected ? Colors.green : Colors.grey,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Text('$_connectionStatus  •  $_latencyMs ms'),
                const Spacer(),
                if (_isConnected)
                  TextButton(
                    onPressed: () {},
                    child: const Text('Request Control'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: _isConnected && _frameAvailable
                  ? _buildRemoteScreen()
                  : _buildConnectPlaceholder(),
            ),
          ),
          if (_isConnected) _buildControlToolbar(),
        ],
      ),
    );
  }

  Widget _buildRemoteScreen() {
    return Container(
      color: Colors.black,
      child: GestureDetector(
        onTapDown: (details) {
          _conn.injectTouch(
            details.localPosition.dx,
            details.localPosition.dy,
            true,
          );
        },
        onTapUp: (details) {
          _conn.injectTouch(
            details.localPosition.dx,
            details.localPosition.dy,
            false,
          );
        },
        onPanUpdate: (details) {
          _conn.injectTouch(
            details.localPosition.dx,
            details.localPosition.dy,
            true,
          );
        },
        child: Image.network(
          'http://placeholder/frame',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.device_unknown, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Remote screen not available',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectPlaceholder() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.devices_other, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('Not connected to remote device'),
        SizedBox(height: 8),
        Text(
          'Start unattended access to accept connections',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildControlToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(Icons.fullscreen_exit, 'Exit Fullscreen', () {}),
          _controlButton(Icons.input, 'Send Ctrl+Alt+Del', () {
            _conn.injectKey(28, true);
            _conn.injectKey(66, true);
            _conn.injectKey(121, true);
            _conn.injectKey(121, false);
            _conn.injectKey(66, false);
            _conn.injectKey(28, false);
          }),
          _controlButton(Icons.keyboard, 'Keyboard', () {
            _showKeyboardDialog(context);
          }),
          _controlButton(Icons.refresh, 'Refresh', () {
            _conn.captureFrame();
          }),
          _controlButton(Icons.link_off, 'Disconnect', _disconnect),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, String label, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: Icon(icon), onPressed: onPressed),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _showKeyboardDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send Key'),
        content: const Text(
          'Keyboard input injection coming in next build.',
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

  void _disconnect() {
    _conn.disconnect();
    setState(() {
      _isConnected = false;
      _connectionStatus = 'disconnected';
    });
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _conn.dispose();
    super.dispose();
  }