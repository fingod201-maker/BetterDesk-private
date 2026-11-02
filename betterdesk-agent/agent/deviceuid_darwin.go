//go:build darwin

package agent

import (
	"fmt"
	"os/exec"
	"strings"
)

// machineUID returns the macOS IOPlatformUUID.
func machineUID() (string, error) {
	out, err := exec.Command("ioreg", "-rd1", "-c", "IOPlatformExpertDevice").Output()
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(out), "\n") {
		if !strings.Contains(line, `"IOPlatformUUID"`) {
			continue
		}
		if _, val, ok := strings.Cut(strings.TrimSpace(line), "= "); ok {
			return strings.Trim(val, `"`), nil
		}
	}
	return "", fmt.Errorf("IOPlatformUUID not found in ioreg output")
}
