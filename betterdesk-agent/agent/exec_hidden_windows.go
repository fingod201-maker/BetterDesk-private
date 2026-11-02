//go:build windows

package agent

import (
	"context"
	"os/exec"
	"syscall"
)

// execCommand builds a child process that never flashes a console window.
//
// The agent may run either as a Windows service (session 0) or as a per-user
// process spawned by the desktop client. In the latter case the agent is a
// console-subsystem binary: without HideWindow every helper it launches
// (ffmpeg, powershell, …) would pop a black terminal window on the user's
// desktop. Agents are required to run silently, so the window is suppressed
// here.
func execCommand(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd
}

// execCommandContext is execCommand with a context.
func execCommandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd
}
