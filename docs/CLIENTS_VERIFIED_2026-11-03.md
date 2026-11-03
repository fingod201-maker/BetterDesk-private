# BetterDesk / Zoom-Private client verification - 2026-11-03

Branch: `operational-v2-ALLclient-working`

## Client matrix

| OS / client | Build formats | Install / run scripts | Live stream | Remote mouse |
|---|---|---|---|---|
| Windows x64 | `betterdesk-agent.exe`, `betterdesk-agent-client.exe`, `BetterDesk-Agent-Setup-x64.exe`, `BetterDesk-Agent-x64.msi` | `Install-ZoomPrivate.vbs`, `Install-ZoomPrivate.cmd`, `Setup-BetterDesk.vbs`, `Start-ZoomPrivate.cmd`, `Stop-ZoomPrivate.cmd`; user-session task runs `%APPDATA%\betterdesk\agent\start-agent.vbs` + `agent-launch.cmd` | Build PASS (windows/amd64, windows/arm64); live requires a Windows cloud host (not this PC) | `SendInput` absolute move/click/scroll; virtual mouse in web console |
| macOS arm64 / amd64 | `.app`, `.dmg`, `.pkg`, `.zip`, `.tar.gz`, standalone `betterdesk-agent` | `Install-ZoomPrivate.command`, `install-zoom-private.sh`, `install.sh`, `start-zoom-private.sh`, `stop-zoom-private.sh` | PASS on GitHub macOS cloud runner (1920x1080 MJPEG) | PASS - virtual mouse click opened Finder; macOS input uses cliclick/osascript |
| Linux x86_64 | `.AppImage`, standalone `betterdesk-agent` | `install-zoom-private.sh`, `install.sh`, `start-zoom-private.sh`, `stop-zoom-private.sh`; systemd user unit + XDG autostart | PASS in Oracle Cloud Podman + Xvfb (1920x1080 MJPEG) | PASS - mouse down/up + keyboard text verified; blocking `xdotool --sync` removed |
| Android universal | `BetterDesk-Client-universal-release.apk`, `BetterDesk-Client-arm64-v8a-release.apk`, `zoom-private-universal-release.apk` | `adb install -r <apk>`; open Zoom-Private app | App starts and auto-connect UI appears; Oracle peer `BD-05F3BBD051CC` is currently OFFLINE, so Android stream is not visible in the Oracle console | N/A (mobile target) |

## Paths

| OS | Directory |
|---|---|
| Windows | `distro/clients/windows/` |
| macOS | `distro/clients/macos/` |
| Linux | `distro/clients/linux/` |
| Android | `distro/clients/android/` |

## Remote web console mouse

`web-nodejs/views/remote.ejs`, `web-nodejs/public/js/remote.js`,
`web-nodejs/public/js/rdclient/cdap-adapter.js`:

- CDAP toolbar auto-expands; Terminal, Keyboard, virtual mouse, L/M/R visible
- visible virtual pointer follows mouse/touch and sends absolute coordinates
- click = left click; toolbar L/M/R = other buttons; wheel supported
- pointer release is forwarded on canvas/document mouseup and blur
- works for Windows, macOS and Linux agents through the same CDAP input path

## Cloud hosting note

- Linux client is hosted on Oracle Cloud and kept online.
- macOS client runs on GitHub Actions cloud runners.
- Windows and Android 24/7 live testing require configured cloud hosts:
  Windows VM/runner with an interactive desktop and an Android cloud device
  with MediaProjection permission. The local PC is not used as a server or
  Windows/macOS/Linux client.
