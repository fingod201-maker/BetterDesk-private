# BetterDesk Client Distribution Package

## Contents

### Android Mobile Client (unattended access)
| File | ABI | Size | Purpose |
|------|-----|------|---------|
| `android/BetterDesk-Client-arm64-v8a-release.apk` | arm64-v8a | 10,360,594 | 64-bit Android devices |
| `android/BetterDesk-Client-armeabi-v7a-release.apk` | armeabi-v7a | 9,810,072 | 32-bit Android devices |

### Windows Desktop Clients
| File | Type | Size | Purpose |
|------|------|------|---------|
| `windows/betterdesk-agent.exe` | Go sidecar binary | 7,089,152 | CDAP agent sidecar (managed by Tauri app or NSSM service) |
| `windows/BetterDesk Agent_1.0.0_x64-setup.exe` | NSIS installer | 4,950,464 | Interactive Windows desktop client installer |
| `windows/BetterDesk Agent_1.0.0_x64_en-US.msi` | MSI installer | 6,586,368 | Enterprise Windows desktop client installer (silent deploy) |
| `windows/betterdesk-agent-client.exe` | Portable binary | 6,710,784 | Standalone desktop client (no install) |

### Configuration
| File | Purpose |
|------|---------|
| `config/branding.json` | Production branding: zoom logo (`#0753FB`), `allow_unattended: true` |
| `config/agent-config.json.example` | Pre-configured agent config template - fill `server_address` + `api_key` |

### Windows Service (system-level, survives logout)
| File | Purpose |
|------|---------|
| `service/nssm.exe` | NSSM service manager (v2.24) |
| `service/betterdesk-agent.exe` | Go sidecar binary for service |
| `service/agent-config.json` | Service config (pre-configured) |

## Installation Instructions

### Windows Desktop Client (operator machine)
1. Run `BetterDesk Agent_1.0.0_x64-setup.exe` or `BetterDesk Agent_1.0.0_x64_en-US.msi`
2. The app installs with the zoom-branded icon
3. On first launch, configure server address in Settings
4. Register device with the BetterDesk web console

### Windows Agent Service (unattended device, system-level)
Requires Administrator PowerShell:

```powershell
# Copy service files to target machine
# C:\ProgramData\BetterDesk\agent\

# Edit agent-config.json with your server address and API key
# Set "access_mode": "unattended" for unattended access

# Install service via NSSM
C:\Path\To\nssm.exe install BetterDeskAgent "C:\ProgramData\BetterDesk\agent\betterdesk-agent.exe" "-config C:\ProgramData\BetterDesk\agent\agent-config.json"
C:\Path\To\nssm.exe set BetterDeskAgent Start SERVICE_AUTO_START
C:\Path\To\nssm.exe set BetterDeskAgent ObjectName LocalSystem
C:\Path\To\nssm.exe set BetterDeskAgent AppDirectory "C:\ProgramData\BetterDesk\agent"
C:\Path\To\nssm.exe set BetterDeskAgent Description "BetterDesk Agent - CDAP device agent"

# Start service
sc start BetterDeskAgent
```

The service runs as `LocalSystem`, starts on boot, and survives user logout.

### Android Mobile Client
1. Install the appropriate APK for your device architecture:
   - `arm64-v8a` for modern 64-bit Android devices
   - `armeabi-v7a` for older 32-bit Android devices
2. On first launch, grant permissions (one-time setup wizard)
3. The app auto-connects to the configured operator server

### Code Signing Status
⚠️ **No code signing certificates were found in the repository or Windows certificate store.**
- Windows SmartScreen may flag unsigned executables on first run
- macOS Gatekeeper will flag unsigned apps as "unidentified developer"
- To resolve: obtain a code signing certificate (DigiCert, Sectigo, etc.) and sign:
  - Windows: `signtool sign /f cert.pfx /p <password> /t http://timestamp.digicert.com <file.exe>`
  - macOS: `codesign --sign "Developer ID Application: <name>" <file.app>`
  - Linux: use `gpg --detach-sign` for package verification

### macOS / Linux Clients
Not built in this environment (Windows-only build machine). To build:
- macOS: Run `npx tauri build --targets macos` on a Mac with Xcode installed
- Linux: Run `npx tauri build --targets linux` on a Linux machine with GTK/WebKitGTK

## Connection Path

Agent → Web Console:
1. Agent sends heartbeat to `POST :21114/api/heartbeat` every 12s
2. Device appears as ONLINE in BetterDesk web console (port 5000)
3. Operator initiates remote session from console
4. Agent shows consent dialog (supervised mode) or accepts immediately (unattended mode)
5. Go sidecar establishes CDAP WebSocket on `:21122/cdap`
6. Remote desktop casting begins (screen capture, input, audio, clipboard)

## Unattended Access Configuration

Edit `agent-config.json`:
```json
{
  "server_address": "https://your-betterdesk-server:5443",
  "api_key": "your-api-key-from-console",
  "access_mode": "unattended",
  "require_consent": false,
  "autostart": true,
  "auto_start_sidecar": true,
  "enforce_tls": true
}
```

## Verified Builds
- Android arm64-v8a APK: built and verified (contains libbetterdesk_flutter_android.so)
- Android armeabi-v7a APK: built and verified (contains libbetterdesk_flutter_android.so)
- Windows Go sidecar: built and verified (`betterdesk-agent 1.0.0`)
- Windows Tauri desktop: built and verified (NSIS + MSI installers)
