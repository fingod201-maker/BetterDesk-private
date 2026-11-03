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
