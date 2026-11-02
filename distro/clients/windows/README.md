# BetterDesk Windows agent (user-session)

This is the working Windows launch setup used in production. The agent runs in
the logged-in user's interactive session, not as a SYSTEM service, so display
capture and input injection target the real desktop. It is started hidden at
logon by a scheduled task.

## Files

| File | Purpose |
|------|---------|
| `start-agent.vbs` | Hidden launcher (`wscript.exe //B start-agent.vbs`) |
| `agent-launch.cmd` | Runs the agent and appends stdout/stderr to `agent.log` |
| `install-agent-task.ps1` | Registers the logon task and starts it |
| `agent-config.example.json` | Config template; replace the device token |

## Layout

- Binary: `%ProgramFiles%\BetterDesk\Agent\betterdesk-agent.exe`
- Config: `%APPDATA%\betterdesk\agent\agent-config.json`
- Log: `%APPDATA%\betterdesk\agent\agent.log`

## Install

1. Copy `betterdesk-agent.exe` to `%ProgramFiles%\BetterDesk\Agent\`.
2. Create the device in the panel, copy its token, and write
   `%APPDATA%\betterdesk\agent\agent-config.json` from
   `agent-config.example.json`.
3. Copy `agent-launch.cmd` and `start-agent.vbs` to
   `%APPDATA%\betterdesk\agent\`.
4. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-agent-task.ps1
```

The task runs as the current user with `Interactive` logon and `Limited`
privileges, hidden via `wscript.exe //B`.

## Windows input fix

`agent-patches/input_windows.go` is the fixed Windows input backend. It removes
the extra trailing pad from `mouseInput`, which made `sizeof(INPUT)` 48 instead
of 40 and caused every `SendInput` call to fail with
`ERROR_INVALID_PARAMETER (87)`. Replace `agent/input_windows.go` in the Go agent
source with this file before rebuilding the Windows agent.

## Why not a service?

A Windows service runs in session 0. The screen capture is blank there and
`SendInput` cannot reach the interactive desktop. Keep the agent in the user
session and use the scheduled task above.
