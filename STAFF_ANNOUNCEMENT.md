# BetterDesk Landing Page — Staff Rollout Announcement

**To:** All Organization Staff  
**From:** IT / BetterDesk Operations  
**Subject:** New Remote Access Portal — zoom.telcom.stream is live  
**Date:** [CURRENT DATE]

---

## 1. What's new

We have published the BetterDesk landing portal at:

> **https://zoom.telcom.stream**

This is your single entry point for:
- Downloading the BetterDesk Agent (auto-detects your OS — Windows, macOS, Linux, Android)
- One-tap unattended install for enrolled devices
- Joining remote support sessions initiated by IT

## 2. What staff need to do

| Role | Action |
|------|--------|
| **End users** | Visit **https://zoom.telcom.stream** from your work device. The page detects your OS and offers the correct installer. Download and run it. |
| **IT / Operators** | Use **https://panel.telcom.stream** (admin console) to view enrolled devices, start remote-control sessions, and manage policies. |
| **Device owners** | If your device is managed/enrolled, the agent auto-connects after install — no manual server entry required. |

## 3. Installer download (auto-detection)

The landing page automatically detects your operating system and serves:

| OS | Installer | Silent / One-tap |
|----|-----------|------------------|
| Windows | `.exe` (NSIS) + `.msi` | Yes — via enrollment token |
| macOS | `.dmg` | Yes |
| Linux | `.deb` / `.AppImage` | Yes |
| Android | `.apk` | Yes — one-tap from mobile browser |

## 4. Admin console (panel.telcom.stream)

Remote control workflow:

1. Log in to **https://panel.telcom.stream** with your org credentials.
2. Select a device from the online device list.
3. Click **Remote** → session starts in your browser (no plugin required).
4. User on the target device sees a consent popup (supervised mode) or connects silently (unattended mode, if policy allows).

## 5. Security notes

- All traffic is TLS-encrypted (HTTPS/WSS).
- Remote sessions require user consent unless unattended mode is explicitly enabled by IT.
- Every session is audit-logged (start/end, permissions used, file transfers).

## 6. Support

- IT helpdesk: [HELPDESK_EMAIL]
- Portal issues: ops@telcom.stream
- Documentation: https://zoom.telcom.stream/privacy

---

**Do not share your admin console credentials. The landing page is public; the admin panel is restricted to authorized IT staff.**
