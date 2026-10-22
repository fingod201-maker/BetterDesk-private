//go:build windows

package agent

import (
	"golang.org/x/sys/windows/registry"
	"strings"
)

// machineUID returns the Windows MachineGuid: unique per OS installation and
// stable across reboots, unlike the hostname which admins routinely change.
func machineUID() (string, error) {
	k, err := registry.OpenKey(registry.LOCAL_MACHINE, `SOFTWARE\Microsoft\Cryptography`, registry.QUERY_VALUE)
	if err != nil {
		return "", err
	}
	defer k.Close()
	v, _, err := k.GetStringValue("MachineGuid")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(v), nil
}
