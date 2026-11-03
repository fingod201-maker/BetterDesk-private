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
