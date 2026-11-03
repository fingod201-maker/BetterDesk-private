//go:build darwin

package agent

import (
	"fmt"
	"os/exec"
	"strings"
	"sync"
)

// mouseDragMu serialises the left-button drag state shared by the
// process-wide cliclick invocations.
var (
	mouseDragMu     sync.Mutex
	mouseDragActive bool
)

// injectInput injects keyboard/mouse events on macOS.
//
// Mouse events use cliclick (https://github.com/BlueM/cliclick) because
// CoreGraphics injection requires cgo; keyboard events use osascript.
// Install cliclick once with: brew install cliclick
// and grant Accessibility + Screen Recording in System Settings.
func injectInput(evt *InputEvent) error {
	switch evt.Type {
	case "mouse_move":
		return darwinMouseMove(evt.X, evt.Y)

	case "mouse_click":
		if err := darwinMouseMove(evt.X, evt.Y); err != nil {
			return err
		}
		return cliclick(darwinClickCommand(evt.Button))

	case "mouse_down":
		if err := darwinMouseMove(evt.X, evt.Y); err != nil {
			return err
		}
		switch evt.Button {
		case 2:
			// cliclick has no right-button down/up split; a right click is
			// atomic. Do it once on press so we do not double-click.
			return cliclick(fmt.Sprintf("rc:%d,%d", evt.X, evt.Y))
		case 3:
			// cliclick has no middle-button command.
			return nil
		default:
			mouseDragMu.Lock()
			defer mouseDragMu.Unlock()
			mouseDragActive = true
			return cliclick(fmt.Sprintf("dd:%d,%d", evt.X, evt.Y))
		}

	case "mouse_up":
		switch evt.Button {
		case 2, 3:
			return nil
		default:
			mouseDragMu.Lock()
			defer mouseDragMu.Unlock()
			mouseDragActive = false
			return cliclick(fmt.Sprintf("du:%d,%d", evt.X, evt.Y))
		}

	case "mouse_scroll":
		if evt.DeltaY == 0 && evt.DeltaX == 0 {
			return nil
		}
		step := evt.DeltaY
		if step == 0 {
			step = evt.DeltaX
		}
		// cliclick cannot scroll; use System Events arrow-key scrolling as a
		// deterministic fallback.
		dir := "down"
		if step < 0 {
			dir = "up"
		}
		count := abs(step) / 100
		if count < 1 {
			count = 1
		}
		if count > 20 {
			count = 20
		}
		for i := 0; i < count; i++ {
			if err := osascript(fmt.Sprintf(`tell application "System Events" to scroll %s 1`, dir)); err != nil {
				return err
			}
		}
		return nil

	case "key_tap", "key_press":
		key, kind, mods := darwinKey(evt.Key, evt.Modifiers)
		if key == "" {
			return nil
		}
		return osascript(buildKeyScript(key, kind, mods))

	case "key_release":
		// osascript cannot hold a key down; key_press already emits a full
		// keystroke, so releasing is a no-op.
		return nil

	case "text":
		if evt.Text == "" {
			return nil
		}
		return osascript(fmt.Sprintf(`tell application "System Events" to keystroke "%s"`, escapeAppleScript(evt.Text)))

	default:
		return fmt.Errorf("unknown input type: %s", evt.Type)
	}
}

func darwinMouseMove(x, y int) error {
	mouseDragMu.Lock()
	dragging := mouseDragActive
	mouseDragMu.Unlock()
	if dragging {
		return cliclick(fmt.Sprintf("dm:%d,%d", x, y))
	}
	return cliclick(fmt.Sprintf("m:%d,%d", x, y))
}

func cliclick(args ...string) error {
	path, err := exec.LookPath("cliclick")
	if err != nil {
		return fmt.Errorf(
			"cliclick not found - mouse injection requires cliclick: brew install cliclick\n" +
				"Also enable Accessibility permission in System Settings > Privacy & Security > Accessibility",
		)
	}
	out, err := execCommand(path, args...).CombinedOutput()
	if err != nil {
		// Detect Accessibility permission denial (common on macOS 14+).
		if strings.Contains(string(out), "permission") || strings.Contains(string(out), "not allowed") {
			return fmt.Errorf(
				"cliclick access denied - enable Accessibility permission in System Settings > Privacy & Security > Accessibility for BetterDesk Agent",
			)
		}
		return fmt.Errorf("cliclick: %w (output: %s)", err, string(out))
	}
	return nil
}

func osascript(script string) error {
	return execCommand("osascript", "-e", script).Run()
}

func darwinClickCommand(button int) string {
	switch button {
	case 2:
		return "rc:."
	default:
		return "c:."
	}
}

// darwinVirtualKeys maps CDAP key names to macOS virtual key codes used by
// AppleScript `key code`.
var darwinVirtualKeys = map[string]int{
	"Return": 36, "Enter": 36,
	"Backspace": 51,
	"Delete":    117, "Del": 117,
	"Escape": 53, "Esc": 53,
	"Tab":   48,
	"Space": 49,
	"ArrowUp": 126, "Up": 126,
	"ArrowDown": 125, "Down": 125,
	"ArrowLeft": 123, "Left": 123,
	"ArrowRight": 124, "Right": 124,
	"Home": 115, "End": 119,
	"PageUp": 116, "PageDown": 121,
	"F1": 122, "F2": 120, "F3": 99, "F4": 118,
	"F5": 96, "F6": 97, "F7": 98, "F8": 100,
	"F9": 101, "F10": 109, "F11": 103, "F12": 111,
}

// darwinKey returns (value, kind, modifiers). kind is "keycode" or "keystroke".
func darwinKey(key string, modifiers []string) (string, string, []string) {
	kind := "keystroke"
	value := key
	if code, ok := darwinVirtualKeys[key]; ok {
		kind = "keycode"
		value = fmt.Sprintf("%d", code)
	} else if len([]rune(key)) != 1 {
		return "", "", nil
	}

	var mods []string
	for _, mod := range modifiers {
		switch strings.ToLower(mod) {
		case "ctrl", "control":
			mods = append(mods, "control down")
		case "alt", "option":
			mods = append(mods, "option down")
		case "shift":
			mods = append(mods, "shift down")
		case "super", "meta", "cmd", "command", "win":
			mods = append(mods, "command down")
		}
	}
	return value, kind, mods
}

func buildKeyScript(value, kind string, mods []string) string {
	using := ""
	if len(mods) > 0 {
		using = " using {" + strings.Join(mods, ", ") + "}"
	}
	if kind == "keycode" {
		return fmt.Sprintf(`tell application "System Events" to key code %s%s`, value, using)
	}
	return fmt.Sprintf(`tell application "System Events" to keystroke "%s"%s`, escapeAppleScript(value), using)
}

func escapeAppleScript(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
