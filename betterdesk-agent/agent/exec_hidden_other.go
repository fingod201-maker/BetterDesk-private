//go:build !windows

package agent

import (
	"context"
	"os/exec"
)

// execCommand builds a child process (no window suppression needed on Unix).
func execCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}

// execCommandContext is execCommand with a context.
func execCommandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, name, args...)
}
