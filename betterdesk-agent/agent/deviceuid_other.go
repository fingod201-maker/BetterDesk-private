//go:build !windows && !darwin && !linux

package agent

import "os"

func machineUID() (string, error) {
	return os.Hostname()
}
