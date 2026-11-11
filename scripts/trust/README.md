# Self-signed publisher trust bootstrap

Use these scripts to trust your in-house self-signed code-signing certificate on managed devices.
Distribute the public certificate (not the private key) with your MDM or alongside the client zip.

- Windows: `powershell -ExecutionPolicy Bypass -File trust-windows.ps1 -CertPath publisher.cer`
- macOS: `bash trust-macos.sh publisher.cer`
- Linux: `bash trust-linux.sh publisher.crt`

After trust is established, SmartScreen/Gatekeeper will not block your signed builds.
MDM allowlisting can deploy the same certificate and app hash without per-OS vendor certs.

See `mdm/` for the managed-deployment package (Intune detection rule, macOS
configuration profile, Linux managed install, allowlist manifest and pinned
checksums) — installing through the MDM is what removes the Mark-of-the-Web /
quarantine flag and therefore the prompts.
