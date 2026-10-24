import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';

/// Bridge between Flutter and the native Kotlin/Rust unattended-access layer.
class ConnectionService {
  static const MethodChannel _channel = MethodChannel('betterdesk/unattended');
  static const EventChannel _eventChannel = EventChannel('betterdesk/events');

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final StreamController<RemoteEvent> _eventController =
      StreamController<RemoteEvent>.broadcast();

  Stream<RemoteEvent> get eventStream => _eventController.stream;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  String? _sessionId;
  String? get sessionId => _sessionId;

  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  bool _unattendedEnabled = false;
  bool get unattendedEnabled => _unattendedEnabled;

  bool _hasPassword = false;
  bool get hasPassword => _hasPassword;

  // Embedded operator config (baked at build time)
  String _operatorHost = '';
  int _operatorPort = 21122;
  bool _hasEmbeddedPassword = false;
  String get operatorHost => _operatorHost;
  int get operatorPort => _operatorPort;
  bool get hasEmbeddedPassword => _hasEmbeddedPassword;

  ConnectionService() {
    _setupEventListener();
  }

  void _setupEventListener() {
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) async {
        try {
          final Map<String, dynamic> data = Map<String, dynamic>.from(event);
          final remoteEvent = RemoteEvent.fromJson(data);
          _eventController.add(remoteEvent);
          _handleEvent(remoteEvent);
        } catch (e) {
          // Ignore malformed events
        }
      },
      onError: (error) {},
    );
  }

  void _handleEvent(RemoteEvent event) {
    switch (event.type) {
      case RemoteEventType.statusChanged:
        _status = event.data['status'] == 'connected'
            ? ConnectionStatus.connected
            : ConnectionStatus.disconnected;
        _sessionId = event.data['sessionId'];
        break;
      case RemoteEventType.latencyUpdated:
        _latencyMs = event.data['latencyMs'] ?? 0;
        break;
      case RemoteEventType.unattendedConfig:
        _unattendedEnabled = event.data['enabled'] == true;
        _hasPassword = event.data['hasPassword'] == true;
        break;
      default:
        break;
    }
  }

  Future<Map<String, bool>> getUnattendedConfig() async {
    try {
      final result = await _channel.invokeMethod('getConnectionInfo');
      final Map<String, dynamic> data = Map<String, dynamic>.from(result);
      _unattendedEnabled = data['enabled'] == true;
      _hasPassword = data['hasPassword'] == true;
      _operatorHost = data['operatorHost'] ?? '';
      _operatorPort = data['operatorPort'] ?? 21122;
      _hasEmbeddedPassword = data['hasPassword'] == true;
      return {
        'enabled': _unattendedEnabled,
        'hasPassword': _hasPassword,
      };
    } catch (e) {
      return {'enabled': false, 'hasPassword': false};
    }
  }

  /// Apply embedded operator config from build-time bake-in.
  Future<void> applyEmbeddedConfig({
    required String host,
    required int port,
    required String passwordHash,
  }) async {
    _operatorHost = host;
    _operatorPort = port;
    _hasEmbeddedPassword = passwordHash.isNotEmpty;
    _unattendedEnabled = passwordHash.isNotEmpty;

    try {
      await _channel.invokeMethod('setEmbeddedConfig', {
        'host': host,
        'port': port,
        'passwordHash': passwordHash,
      });
    } catch (e) {
      // Native layer may not be running yet
    }
  }

  /// Auto-connect to the operator webconsole using embedded config.
  /// Called once on first launch after user grants permission.
  Future<bool> autoConnectToOperator() async {
    if (_operatorHost.isEmpty) return false;

    _status = ConnectionStatus.connecting;
    _eventController.add(RemoteEvent(
      type: RemoteEventType.statusChanged,
      data: {'status': 'connecting'},
    ));

    try {
      // In the full build, this establishes a TCP connection to the operator
      // webconsole and performs the password handshake using the embedded hash.
      await Future.delayed(const Duration(seconds: 2));
      _status = ConnectionStatus.authenticated;
      _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      _eventController.add(RemoteEvent(
        type: RemoteEventType.statusChanged,
        data: {
          'status': 'connected',
          'sessionId': _sessionId,
        },
      ));
      return true;
    } catch (e) {
      _status = ConnectionStatus.error;
      _eventController.add(RemoteEvent(
        type: RemoteEventType.error,
        data: {'message': e.toString()},
      ));
      return false;
    }
  }

  Future<void> setPermanentPassword(String password) async {
    await _storage.write(
      key: 'betterdesk_permanent_password',
      value: password,
    );
    try {
      await _channel.invokeMethod('setPermanentPassword', password);
    } catch (e) {
      // Native layer may not be running yet
    }
  }

  Future<void> clearPermanentPassword() async {
    await _storage.delete(key: 'betterdesk_permanent_password');
    try {
      await _channel.invokeMethod('setPermanentPassword', '');
    } catch (e) {}
  }

  Future<bool> connect({
    required String host,
    required int port,
    required bool useHttps,
    String? password,
  }) async {
    _status = ConnectionStatus.connecting;
    _eventController.add(RemoteEvent(
      type: RemoteEventType.statusChanged,
      data: {'status': 'connecting'},
    ));

    try {
      await Future.delayed(const Duration(seconds: 2));
      _status = ConnectionStatus.authenticated;
      _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      _eventController.add(RemoteEvent(
        type: RemoteEventType.statusChanged,
        data: {
          'status': 'connected',
          'sessionId': _sessionId,
        },
      ));
      return true;
    } catch (e) {
      _status = ConnectionStatus.error;
      _eventController.add(RemoteEvent(
        type: RemoteEventType.error,
        data: {'message': e.toString()},
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    _status = ConnectionStatus.disconnected;
    _sessionId = null;
    _eventController.add(RemoteEvent(
      type: RemoteEventType.statusChanged,
      data: {'status': 'disconnected'},
    ));
  }

  Future<void> injectTouch(double x, double y, bool down) async {
    try {
      await _channel.invokeMethod('injectTouch', {
        'x': x,
        'y': y,
        'down': down,
      });
    } catch (e) {}
  }

  Future<void> injectKey(int keyCode, bool down) async {
    try {
      await _channel.invokeMethod('injectKey', {
        'keyCode': keyCode,
        'down': down,
      });
    } catch (e) {}
  }

  Future<Map<String, dynamic>?> captureFrame() async {
    try {
      final result = await _channel.invokeMethod('captureFrame');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveServerConfig({
    required String host,
    required bool useHttps,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setBool('use_https', useHttps);
    await _storage.write(key: 'betterdesk_server_host', value: host);
  }

  Future<Map<String, dynamic>> loadServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final host = await _storage.read(key: 'betterdesk_server_host') ??
        prefs.getString('server_host') ??
        '';
    final useHttps = await _storage.read(key: 'betterdesk_use_https') != null
        ? await _storage.read(key: 'betterdesk_use_https') == 'true'
        : prefs.getBool('use_https') ?? false;
    return {'host': host, 'useHttps': useHttps};
  }

  void dispose() {
    _eventController.close();
  }
}

/// Events from the native layer.
class RemoteEvent {
  final RemoteEventType type;
  final Map<String, dynamic> data;

  RemoteEvent({required this.type, required this.data});

  factory RemoteEvent.fromJson(Map<String, dynamic> json) {
    return RemoteEvent(
      type: RemoteEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RemoteEventType.unknown,
      ),
      data: Map<String, dynamic>.from(json['data'] ?? {}),
    );
  }
}

enum RemoteEventType {
  statusChanged,
  latencyUpdated,
  unattendedConfig,
  frameReady,
  error,
  unknown,
}