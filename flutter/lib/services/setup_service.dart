import 'package:flutter/services.dart';

/// Aggregate setup status reported by the native side.
class SetupStatus {
  final bool notifications;
  final bool accessibility;
  final bool batteryExempt;
  final bool screenCapture;
  final bool serviceRunning;

  /// True on Android 13+ when the app was sideloaded and Android is blocking
  /// the Accessibility toggle until "Allow restricted settings" is enabled.
  final bool restrictedSettingsRequired;

  SetupStatus({
    required this.notifications,
    required this.accessibility,
    required this.batteryExempt,
    required this.screenCapture,
    required this.serviceRunning,
    required this.restrictedSettingsRequired,
  });

  factory SetupStatus.fromJson(Map<String, dynamic> json) => SetupStatus(
        notifications: json['notifications'] == true,
        accessibility: json['accessibility'] == true,
        batteryExempt: json['batteryExempt'] == true,
        screenCapture: json['screenCapture'] == true,
        serviceRunning: json['serviceRunning'] == true,
        restrictedSettingsRequired: json['restrictedSettingsRequired'] == true,
      );

  /// Required for unattended access: notifications, remote control
  /// (accessibility), and screen share (MediaProjection). Battery
  /// exemption is strongly recommended but not blocking.
  bool get requiredGranted => notifications && accessibility && screenCapture;
  bool get allGranted => requiredGranted && batteryExempt;
}

/// Bridge to MainActivity's `betterdesk/setup` method channel.
class SetupService {
  static const MethodChannel _channel = MethodChannel('betterdesk/setup');

  Future<SetupStatus> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getSetupStatus');
      return SetupStatus.fromJson(Map<String, dynamic>.from(result));
    } catch (_) {
      // Also covers MissingPluginException in the headless service engine.
      return SetupStatus(
        notifications: false,
        accessibility: false,
        batteryExempt: false,
        screenCapture: false,
        serviceRunning: false,
        restrictedSettingsRequired: false,
      );
    }
  }

  Future<SetupStatus> requestNotificationPermission() async {
    final result = await _channel.invokeMethod('requestNotificationPermission');
    return SetupStatus.fromJson(Map<String, dynamic>.from(result));
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod('isAccessibilityEnabled') == true;
    } on PlatformException {
      return false;
    }
  }

  Future<SetupStatus> openAccessibilitySettings() async {
    final result = await _channel.invokeMethod('openAccessibilitySettings');
    return SetupStatus.fromJson(Map<String, dynamic>.from(result));
  }

  /// Opens the app's system info page, where Android 13+ shows the
  /// three-dot menu entry "Allow restricted settings".
  Future<SetupStatus> openAppDetailsSettings() async {
    final result = await _channel.invokeMethod('openAppDetailsSettings');
    return SetupStatus.fromJson(Map<String, dynamic>.from(result));
  }

  Future<SetupStatus> requestBatteryExemption() async {
    final result = await _channel.invokeMethod('requestBatteryExemption');
    return SetupStatus.fromJson(Map<String, dynamic>.from(result));
  }

  Future<SetupStatus> requestScreenCapture() async {
    final result = await _channel.invokeMethod('requestScreenCapture');
    return SetupStatus.fromJson(Map<String, dynamic>.from(result));
  }
}
