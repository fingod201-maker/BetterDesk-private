# MDM allowlist for the in-house zoom-private client

Goal: staff install the client without a SmartScreen ("Windows protected your PC")
or Gatekeeper ("cannot be opened because the developer cannot be verified") prompt.

The reliable, budget-free way to get there is **managed deployment**: when the
payload is delivered by the MDM instead of downloaded in a browser, it never
receives the Windows Mark-of-the-Web and never receives the macOS
`com.apple.quarantine` flag — so neither SmartScreen nor Gatekeeper has a reason
to prompt. Pair that with trusting the in-house publisher certificate and the
client installs silently.

## What is in this folder

| File | Purpose |
|---|---|
| `allowlist.json` | Machine-readable manifest: bundle names, install paths, config dirs, detection rules, publisher cert. |
| `windows-intune-detection.xml` | Intune Win32 app detection + install command (runs `install.ps1` with the panel address). |
| `macos-managed-install.mobileconfig` | Jamf/Intune macOS profile that installs the `.app` as a managed app. |
| `linux-managed-install.sh` | Linux managed install: `/opt/zoom-private`, systemd unit, trust store, config seed. |
| `update-checksums.ps1` | Regenerates `checksums.sha256` from the published release (pins known-good bundles). |
| `checksums.sha256` | SHA-256 of the currently published bundles. |

## One-time setup

1. **Create the publisher certificate** (one per organisation, free with
   `New-SelfSignedCertificate` on a build host) and export the public part as
   `scripts/trust/publisher.cer`. Sign the Windows binaries with it and
   notarise the macOS app with it.
2. **Deploy the certificate to device trust stores** with the scripts one level
   up:
   - Windows: `powershell -ExecutionPolicy Bypass -File scripts/trust/trust-windows.ps1 -CertPath publisher.cer`
   - macOS: `bash scripts/trust/trust-macos.sh publisher.cer`
   - Linux: `bash scripts/trust/trust-linux.sh publisher.crt`
3. **Import the bundles into the MDM** as managed apps:
   - Windows (Intune): upload `zoom-private-windows-x64.zip`, use
     `windows-intune-detection.xml` as the detection rule.
   - macOS (Jamf/Intune): stage `zoom-private.agent.app` and upload
     `macos-managed-install.mobileconfig` (replace `PAYLOAD_PATH`).
   - Linux (Workspace ONE / Ansible): run `linux-managed-install.sh` with the
     panel address.
4. **Pin the checksums** — run `update-checksums.ps1` after each release and
   have the MDM verify the bundle hash before installing.

## Fallback for unmanaged devices

Staff who install manually from the landing page unzip the bundle and run one
command:

- Windows: `powershell -ExecutionPolicy Bypass -File .\install.ps1 -ServerAddress https://panel.telcom.stream`
- macOS / Linux: `bash install.sh https://panel.telcom.stream`

The macOS installer clears `com.apple.quarantine`, so the app launches right
after unzipping even without a signing certificate.
