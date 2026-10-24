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

  /// Operator endpoint baked into the APK resources by CI.
  Future<Map<String, dynamic>> getBakedServerConfig() async {
    try {
      final result = await _channel.invokeMethod('getBakedServerConfig');
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return const {};
    }
  }

  /// Live state of the outbound relay dialer: idle|starting|registering|
  /// connected|streaming|failed, plus the enrolled device id.
  Future<Map<String, dynamic>> getRelayStatus() async {
    try {
      final result = await _channel.invokeMethod('getRelayStatus');
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return const {'state': 'idle', 'deviceId': ''};
    }
  }

  /// Starts the persistent unattended-access service (foreground service),
  /// which registers the device and opens the outbound relay connection.
  Future<bool> startUnattendedAccess() async {
    try {
      return await _channel.invokeMethod('startUnattendedAccess') == true;
    } catch (_) {
      return false;
    }
  }

  /// Device-owner fleets: silently grants runtime permissions when the app
  /// holds device-owner/profile-owner rights. No-op on ordinary installs.
  Future<Map<String, dynamic>> grantAllSilently() async {
    try {
      final result = await _channel.invokeMethod('grantAllSilently');
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return const {'deviceOwner': false};
    }
  }

  /// Sends the app to the background after the device is connected so the
  /// persistent service keeps running with minimal footprint.
  Future<void> moveToBackground() async {
    try {
      await _channel.invokeMethod('moveToBackground');
    } catch (_) {}
  }

  /// The single privileged permission for the one-tap flow: activates the
  /// device admin (one system dialog on consumer devices; already active on
  /// device-owner fleets). Returns true once the admin is active.
  Future<bool> requestDeviceAdmin() async {
    try {
      return await _channel.invokeMethod('requestDeviceAdmin') == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDeviceAdmin() async {
    try {
      return await _channel.invokeMethod('isDeviceAdmin') == true;
    } catch (_) {
      return false;
    }
  }

  /// Enables the remote-control accessibility service with no user dialog when
  /// the app is device owner or was provisioned with WRITE_SECURE_SETTINGS
  /// (the fleet/emulator setup script grants this over adb). Returns true once
  /// accessibility is live. On a plain consumer install it returns false and
  /// the wizard shows the single Accessibility toggle instead.
  Future<bool> enableAccessibilitySilently() async {
    try {
      return await _channel.invokeMethod('enableAccessibilitySilently') == true;
    } catch (_) {
      return false;
    }
  }

  /// Arms the accessibility auto-grant window so the accessibility service
  /// accepts the residual system dialogs during the one-tap setup.
  Future<void> armAutoGrant() async {
    try {
      await _channel.invokeMethod('armAutoGrant');
    } catch (_) {}
  }

  /// Post-connection stealth mode: makes the window invisible and
  /// non-interactive, then sends the task to the background.
  Future<void> setInvisible() async {
    try {
      await _channel.invokeMethod('setInvisible');
    } catch (_) {}
  }
}
