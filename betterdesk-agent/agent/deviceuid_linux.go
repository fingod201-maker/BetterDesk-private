//go:build linux

package agent

import (
	"fmt"
	"os"
	"strings"
)

// machineUID returns the Linux machine-id (stable, unique per install).
func machineUID() (string, error) {
	for _, path := range []string{"/etc/machine-id", "/var/lib/dbus/machine-id"} {
		data, err := os.ReadFile(path)
		if err == nil {
			if id := strings.TrimSpace(string(data)); id != "" {
				return id, nil
			}
		}
	}
	return "", fmt.Errorf("no machine-id file under /etc/machine-id or /var/lib/dbus/machine-id")
}
