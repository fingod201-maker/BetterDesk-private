# BetterDesk — Android Emulator Test Guide

Tests the full staff/customer journey on Android emulators before publishing
zoom.telcom.stream globally:

1. APK auto-download from landing page (OS auto-detection)
2. APK installation + permission grants
3. Agent registration + online status in admin console
4. Remote-control session initiated from panel → accepted on emulator

## Prerequisites (on your test machine)

```bash
# Install Android SDK command-line tools (or Android Studio)
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/emulator
```

## Step 1 — Create emulator AVDs (Android 13/14/15)

```bash
./scripts/android-emulator-setup.sh
```

This creates three AVDs:
- `BD_Android15_API35` — Android 15 (API 35), arm64-v8a, Pixel 6
- `BD_Android14_API34` — Android 14 (API 34), arm64-v8a, Pixel 6
- `BD_Android13_API33` — Android 13 (API 33), arm64-v8a, Pixel 6

## Step 2 — Launch an emulator (separate terminal)

```bash
$ANDROID_HOME/emulator/emulator @BD_Android15_API35 -gpu host -camera-backend none -wipe-data
```

Note the serial (e.g. `emulator-5554`) shown in the window title or via `adb devices`.

## Step 3 — Ensure VPS is deployed & landing page is live

Before testing, the VPS must be running with:
- Nginx terminating SSL on `zoom.telcom.stream` (port 443)
- Landing service on internal port 8080
- Android APK present in `distro/clients/` (universal + arm64)

Deploy first:
```bash
# On the VPS
export CERTBOT_EMAIL=admin@telcom.stream
export RELAY_PUBLIC_IP=<VPS_IP>
export SESSION_SECRET=$(openssl rand -hex 32)
./scripts/deploy-24x7.sh docker
docker compose -f docker-compose.ops.yml --profile init run --rm certbot
./scripts/health-check.sh
```

Upload an APK to the landing service:
```bash
# On your machine or VPS
./scripts/upload-artifacts.sh path/to/BetterDesk-Agent-universal.apk
./scripts/verify-artifacts.sh
```

## Step 4 — Run the test suite (per emulator)

Replace `<serial>` with your emulator's adb serial:

```bash
# 4a. Download APK from landing page (tests OS auto-detection)
./scripts/android-test-apk-download.sh <serial> https://zoom.telcom.stream

# 4b. Install the APK on emulator
./scripts/android-test-install.sh <serial> /sdcard/Download/BetterDesk-Agent.apk

# 4c. Remote control end-to-end (agent → panel → session)
./scripts/android-test-remote-control.sh <serial> https://panel.telcom.stream
```

## Step 5 — Repeat on all Android versions

```bash
# Launch each AVD and repeat steps 4a–4c:
$ANDROID_HOME/emulator/emulator @BD_Android13_API33 -gpu host -camera-backend none   # serial emulator-5554
$ANDROID_HOME/emulator/emulator @BD_Android14_API34 -gpu host -camera-backend none   # serial emulator-5556
$ANDROID_HOME/emulator/emulator @BD_Android15_API35 -gpu host -camera-backend none   # serial emulator-5558
```

## What to verify (pass/fail criteria)

| Check | Pass condition |
|-------|---------------|
| OS auto-detection | Landing page serves `.apk` (not `.exe`/`.dmg`) when accessed from emulator browser |
| APK MIME type | `Content-Type: application/vnd.android.package-archive` on `/download/android` |
| Installation | `adb install` returns `Success`; no "app not installed" error |
| Unknown sources | Signed APK installs without "unknown source" prompt; unsigned prompts and user must allow |
| Agent online | Device appears in admin console device list with status Online |
| Remote control | Console "Remote" button opens browser viewer; emulator user sees consent popup; accepting grants control |
| Android 13/14/15 | All three AVDs pass the above |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `adb: device not found` | Emulator not started; run emulator in another terminal, check `adb devices` |
| Download returns HTML not APK | Landing service not deployed, or APK missing from distro/clients/ |
| Install blocked "unknown source" | Sign the APK (`apksigner sign`) or enable install-unknown-apps for the browser/ADB |
| Device not appearing in console | Agent not enrolled — check `RELAY_PUBLIC_IP` is set to VPS public IP, not Docker internal IP |
| Remote control black screen | Emulator GPU acceleration off; add `-gpu host` to emulator launch |
| Consent popup not shown | Agent accessibility permission not granted; run install script's permission grants |

## Sign-off

| Android version | AVD | Download | Install | Online | Remote control | Pass? |
|-----------------|-----|----------|---------|--------|----------------|-------|
| Android 13 (API 33) | BD_Android13_API33 | | | | | |
| Android 14 (API 34) | BD_Android14_API34 | | | | | |
| Android 15 (API 35) | BD_Android15_API35 | | | | | |

All rows must be "Yes" before publishing zoom.telcom.stream to staff.
