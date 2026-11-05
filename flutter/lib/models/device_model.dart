/// Device model representing a remote device that can be connected to.
class DeviceModel {
  final String id;
  final String name;
  final String host;
  final bool isOnline;
  final DateTime lastSeen;
  final String version;
  final bool unattendedAccess;

  DeviceModel({
    required this.id,
    required this.name,
    required this.host,
    this.isOnline = false,
    required this.lastSeen,
    required this.version,
    this.unattendedAccess = false,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      version: json['version'] as String,
      unattendedAccess: json['unattendedAccess'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'isOnline': isOnline,
      'lastSeen': lastSeen.toIso8601String(),
      'version': version,
      'unattendedAccess': unattendedAccess,
    };
  }

  @override
  String toString() {
    return 'DeviceModel(id: $id, name: $name, host: $host, online: $isOnline)';
  }
}

/// Connection status for a remote session.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  error,
}

/// Remote session information.
class RemoteSession {
  final String sessionId;
  final String deviceId;
  final ConnectionStatus status;
  final DateTime startedAt;
  final int? latencyMs;
  final String? errorMessage;

  RemoteSession({
    required this.sessionId,
    required this.deviceId,
    required this.status,
    required this.startedAt,
    this.latencyMs,
    this.errorMessage,
  });

  bool get isConnected => status == ConnectionStatus.authenticated;
  bool get isConnecting => status == ConnectionStatus.connecting || status == ConnectionStatus.authenticating;

  @override
  String toString() {
    return 'RemoteSession(id: $sessionId, deviceId: $deviceId, status: $status)';
  }
}
