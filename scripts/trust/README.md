# Self-signed publisher trust bootstrap

Use these scripts to trust your in-house self-signed code-signing certificate on managed devices.
Distribute the public certificate (not the private key) with your MDM or alongside the client zip.

- Windows: `powershell -ExecutionPolicy Bypass -File trust-windows.ps1 -CertPath publisher.cer`
- macOS: `bash trust-macos.sh publisher.cer`
- Linux: `bash trust-linux.sh publisher.crt`

After trust is established, SmartScreen/Gatekeeper will not block your signed builds.
MDM allowlisting can deploy the same certificate and app hash without per-OS vendor certs.
