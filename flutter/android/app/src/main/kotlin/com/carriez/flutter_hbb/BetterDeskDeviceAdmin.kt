package com.carriez.flutter_hbb

import android.app.admin.DeviceAdminReceiver

/**
 * Device-owner receiver for zero-touch fleet provisioning.
 *
 * When the device is provisioned with `dpm set-device-owner`, the app can grant
 * the unattended-access permissions (notifications, accessibility) silently,
 * so the operator-managed fleet installs require no user interaction at all.
 */
class BetterDeskDeviceAdmin : DeviceAdminReceiver()
