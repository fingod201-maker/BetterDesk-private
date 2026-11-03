# BetterDesk client verification - 2026-11-03

Branch: `operational-v2-ALLclient-working`

## Production paths

| Client | Binary | Launch / install script | Build | Live stream | Remote mouse |
|---|---|---|---|---|---|
| Windows x64 | `distro/clients/windows/betterdesk-agent.exe` | `Setup-BetterDesk.vbs` (or `install-agent-task.ps1`) | PASS (windows/amd64, windows/arm64) | Not re-run: no configured cloud Windows host; local PC is reserved as control host | `SendInput` absolute move/click/scroll implemented; toolbar L/M/R exposed |
| macOS arm64 | `distro/clients/macos/betterdesk-agent` | `install.sh` -> `install-betterdesk-support.sh`; `build-pkg.sh` for `.pkg` | PASS (darwin/arm64, darwin/amd64) | PASS on GitHub macOS runner (1920x1080 MJPEG) | PASS - click opened Finder |
| Linux x86_64 | `distro/clients/linux/betterdesk-agent` | `install.sh` -> `install-betterdesk-support.sh` | PASS (linux/amd64, linux/arm64) | PASS in Oracle Cloud Podman + Xvfb (1920x1080 MJPEG) | PASS - mouse click + keyboard text verified; removed blocking `xdotool --sync` |
| Android universal | `distro/clients/android/zoom-private-universal-release.apk` | `adb install -r ...` | Prebuilt Flutter/RustDesk 1.5.0 APK; package `com.betterdesk.client.universal` | Blocked: this APK is a RustDesk viewer, while the PC support agent is CDAP; no RustDesk target is configured in the Oracle environment | N/A (viewer) |

## Remote web console mouse controls

`web-nodejs/views/remote.ejs` + `web-nodejs/public/js/remote.js`:

- toolbar auto-expands for CDAP sessions
- Terminal, Keyboard, and L/M/R buttons are visible
- pointer release is forwarded when the pointer leaves the canvas
- optional billing hooks are type-checked so an older panel script cannot abort startup

`web-nodejs/public/js/rdclient/cdap-adapter.js` sends move/click/down/up and
releases buttons on document mouseup/blur.

## Windows / Android limitation

The control PC was not used as a client or server. Windows live verification
requires a configured Windows cloud host or a GitHub Actions runner with an
interactive desktop; the GitHub Windows runner cannot provide a real
interactive session for `SendInput`/desktop capture. The Android APK is a
RustDesk client and cannot consume the CDAP support-agent stream without a
RustDesk target.
