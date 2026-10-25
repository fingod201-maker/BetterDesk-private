//! One-tap OS permission grants for unattended remote access.
//!
//! The desktop client needs four things before an operator can stream and
//! control the machine from the web console:
//!
//! * inbound firewall allowance (direct sessions),
//! * screen-capture consent (macOS TCC; always granted on Windows/Linux),
//! * accessibility / input-injection consent (macOS TCC),
//! * login autostart (handled by [`crate::autostart`]).
//!
//! Every grant that requires elevation is performed through the platform's
//! native consent dialog exactly once: a single UAC prompt on Windows, a single
//! `with administrator privileges` prompt on macOS, and a single `pkexec`
//! prompt on Linux. Nothing is granted silently behind the user's back.

use log::{info, warn};
use serde::Serialize;
use std::path::PathBuf;

/// Ports used by the agent, console and relay for remote sessions.
pub const REMOTE_PORTS: &[(&str, &str)] = &[
    ("21114", "tcp"),
    ("21115", "tcp"),
    ("21116", "tcp"),
    ("21116", "udp"),
    ("21117", "tcp"),
    ("21118", "tcp"),
    ("21119", "tcp"),
    ("5000", "tcp"),
    ("5443", "tcp"),
];

/// Result of a single permission probe.
#[derive(Debug, Clone, Serialize)]
pub struct PermissionStatus {
    pub key: String,
    pub granted: bool,
    pub detail: String,
}

/// Snapshot of everything the single-step setup needs to know.
#[derive(Debug, Clone, Serialize, Default)]
pub struct RemotePermissionReport {
    pub screen_capture: bool,
    pub accessibility: bool,
    pub firewall: bool,
    pub autostart: bool,
    pub details: Vec<PermissionStatus>,
}

impl RemotePermissionReport {
    fn push(&mut self, key: &str, granted: bool, detail: impl Into<String>) {
        self.details.push(PermissionStatus {
            key: key.to_string(),
            granted,
            detail: detail.into(),
        });
    }
}

/// Apply the firewall rules needed for direct remote sessions.
///
/// This is the *only* call in the setup flow that elevates. On Windows it
/// triggers exactly one UAC dialog, on macOS one administrator prompt and on
/// Linux one polkit prompt.
pub fn ensure_firewall() -> Result<(), String> {
    let result = platform::ensure_firewall();
    match &result {
        Ok(()) => info!("[permissions] firewall rules applied"),
        Err(e) => warn!("[permissions] firewall configuration failed: {}", e),
    }
    result
}

/// Ask macOS for Screen Recording consent (no-op / always true elsewhere).
///
/// The call itself presents the system TCC prompt the first time. It returns
/// the current grant state, so a user who already consented sees no dialog.
pub fn request_screen_capture() -> bool {
    platform::request_screen_capture()
}

/// Ask macOS for Accessibility (input injection) consent.
pub fn request_accessibility() -> bool {
    platform::request_accessibility()
}

/// Probe the current permission state without prompting.
pub fn report(autostart_enabled: bool) -> RemotePermissionReport {
    let mut report = RemotePermissionReport::default();

    report.screen_capture = platform::screen_capture_granted();
    report.push(
        "screen_capture",
        report.screen_capture,
        platform::screen_capture_detail(),
    );

    report.accessibility = platform::accessibility_granted();
    report.push(
        "accessibility",
        report.accessibility,
        platform::accessibility_detail(),
    );

    report.firewall = platform::firewall_granted();
    report.push("firewall", report.firewall, platform::firewall_detail());

    report.autostart = autostart_enabled;
    report.push(
        "autostart",
        autostart_enabled,
        if autostart_enabled {
            "Starts with the operating system"
        } else {
            "Autostart is disabled"
        },
    );

    report
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

#[cfg(windows)]
mod platform {
    use super::REMOTE_PORTS;
    use std::process::Command;

    const RULE: &str = "Zoom VIP Remote Access";

    pub fn ensure_firewall() -> Result<(), String> {
        let exe = std::env::current_exe()
            .map_err(|e| format!("Cannot resolve executable path: {}", e))?;
        let exe = exe.to_string_lossy().replace('\'', "''");

        let mut script = String::from("$ErrorActionPreference = 'Stop'\n");
        script.push_str(&format!("$exe = '{}'\n", exe));
        script.push_str(&format!(
            "Get-NetFirewallRule -DisplayName '{0}*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue\n",
            RULE
        ));
        script.push_str(&format!(
            "New-NetFirewallRule -DisplayName '{0}' -Direction Inbound -Program $exe -Action Allow -Profile Any -Enabled True -Description 'Zoom VIP remote desktop (inbound)' | Out-Null\n",
            RULE
        ));
        script.push_str(&format!(
            "New-NetFirewallRule -DisplayName '{0} Out' -Direction Outbound -Program $exe -Action Allow -Profile Any -Enabled True -Description 'Zoom VIP remote desktop (outbound)' | Out-Null\n",
            RULE
        ));
        for (port, proto) in REMOTE_PORTS {
            let protocol = if *proto == "udp" { "UDP" } else { "TCP" };
            script.push_str(&format!(
                "New-NetFirewallRule -DisplayName '{0} {1}/{2}' -Direction Inbound -Protocol {3} -LocalPort {1} -Action Allow -Profile Any -Enabled True | Out-Null\n",
                RULE, port, proto, protocol
            ));
        }
        script.push_str("exit 0\n");

        run_elevated_powershell(&script)
    }

    fn run_elevated_powershell(script: &str) -> Result<(), String> {
        let path = std::env::temp_dir().join(format!(
            "zoom-vip-permissions-{}.ps1",
            std::process::id()
        ));
        std::fs::write(&path, script)
            .map_err(|e| format!("Cannot write permission script: {}", e))?;

        let status = if crate::privileges::is_elevated() {
            // Already running with an elevated token - no second UAC prompt.
            crate::proc::hidden("powershell.exe")
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    &path.to_string_lossy(),
                ])
                .status()
        } else {
            let escaped = path.to_string_lossy().replace('\'', "''");
            let launcher = format!(
                "$ErrorActionPreference='Stop'; try {{ $p = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File','{escaped}' -Verb RunAs -Wait -PassThru -WindowStyle Hidden; exit $p.ExitCode }} catch {{ exit 1223 }}"
            );
            crate::proc::hidden("powershell.exe")
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    &launcher,
                ])
                .status()
        };

        let _ = std::fs::remove_file(&path);

        match status {
            Ok(s) if s.success() => Ok(()),
            Ok(s) => Err(format!(
                "Firewall permission was not granted (exit {})",
                s.code().unwrap_or(-1)
            )),
            Err(e) => Err(format!("Cannot launch the elevation prompt: {}", e)),
        }
    }

    pub fn request_screen_capture() -> bool {
        true
    }

    pub fn request_accessibility() -> bool {
        true
    }

    pub fn screen_capture_granted() -> bool {
        true
    }

    pub fn screen_capture_detail() -> &'static str {
        "Windows allows screen capture without extra consent"
    }

    pub fn accessibility_granted() -> bool {
        true
    }

    pub fn accessibility_detail() -> &'static str {
        "Windows allows input injection without extra consent"
    }

    pub fn firewall_granted() -> bool {
        let output = Command::new("netsh")
            .args([
                "advfirewall",
                "firewall",
                "show",
                "rule",
                &format!("name={}", RULE),
            ])
            .output();
        matches!(output, Ok(o) if o.status.success())
    }

    pub fn firewall_detail() -> &'static str {
        "Ports 21114-21119, 5000 and 5443 are allowed through Windows Firewall"
    }
}

// ---------------------------------------------------------------------------
// macOS
// ---------------------------------------------------------------------------

#[cfg(target_os = "macos")]
mod platform {
    use super::REMOTE_PORTS;
    use std::ffi::c_void;
    use std::process::Command;

    type CFTypeRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFIndex = isize;
    type Boolean = u8;

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGPreflightScreenCaptureAccess() -> Boolean;
        fn CGRequestScreenCaptureAccess() -> Boolean;
    }

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        static kAXTrustedCheckOptionPrompt: CFStringRef;
        fn AXIsProcessTrusted() -> Boolean;
        fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> Boolean;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFBooleanTrue: CFTypeRef;
        fn CFDictionaryCreate(
            allocator: *const c_void,
            keys: *const *const c_void,
            values: *const *const c_void,
            num_values: CFIndex,
            key_call_backs: *const c_void,
            value_call_backs: *const c_void,
        ) -> CFDictionaryRef;
        fn CFRelease(cf: CFTypeRef);
    }

    pub fn request_screen_capture() -> bool {
        unsafe { CGRequestScreenCaptureAccess() != 0 || CGPreflightScreenCaptureAccess() != 0 }
    }

    pub fn request_accessibility() -> bool {
        unsafe {
            if AXIsProcessTrusted() != 0 {
                return true;
            }
            let key: CFStringRef = kAXTrustedCheckOptionPrompt;
            let value: CFTypeRef = kCFBooleanTrue;
            let keys = [key];
            let values = [value];
            let dict = CFDictionaryCreate(
                std::ptr::null(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                std::ptr::null(),
                std::ptr::null(),
            );
            if dict.is_null() {
                return false;
            }
            let trusted = AXIsProcessTrustedWithOptions(dict) != 0;
            CFRelease(dict);
            trusted
        }
    }

    pub fn screen_capture_granted() -> bool {
        unsafe { CGPreflightScreenCaptureAccess() != 0 }
    }

    pub fn screen_capture_detail() -> &'static str {
        "Screen Recording is granted to Zoom VIP in System Settings"
    }

    pub fn accessibility_granted() -> bool {
        unsafe { AXIsProcessTrusted() != 0 }
    }

    pub fn accessibility_detail() -> &'static str {
        "Accessibility is granted to Zoom VIP in System Settings"
    }

    pub fn ensure_firewall() -> Result<(), String> {
        let exe = std::env::current_exe()
            .map_err(|e| format!("Cannot resolve executable path: {}", e))?;

        let mut candidates = vec![exe];
        if let Some(sidecar) = sidecar_path() {
            candidates.push(sidecar);
        }

        let mut shell = String::new();
        for candidate in candidates {
            let path = shell_quote(&candidate.to_string_lossy());
            shell.push_str(&format!(
                "/usr/libexec/ApplicationFirewall/socketfilterfw --add {path} >/dev/null 2>&1 || true; "
            ));
            shell.push_str(&format!(
                "/usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp {path} >/dev/null 2>&1 || true; "
            ));
        }
        let _ = REMOTE_PORTS;

        run_admin(&shell)
    }

    fn sidecar_path() -> Option<std::path::PathBuf> {
        let exe = std::env::current_exe().ok()?;
        let dir = exe.parent()?;
        let direct = dir.join("betterdesk-agent");
        if direct.exists() {
            return Some(direct);
        }
        let macos = dir.join("Contents/MacOS/betterdesk-agent");
        macos.exists().then_some(macos)
    }

    fn shell_quote(value: &str) -> String {
        format!("'{}'", value.replace('\'', "'\\''"))
    }

    fn run_admin(shell: &str) -> Result<(), String> {
        if crate::privileges::is_elevated() {
            let status = crate::proc::hidden("/bin/sh")
                .args(["-c", shell])
                .status()
                .map_err(|e| format!("Cannot run firewall command: {}", e))?;
            return if status.success() {
                Ok(())
            } else {
                Err("Firewall rules could not be applied".to_string())
            };
        }
        let escaped = shell.replace('\\', "\\\\").replace('"', "\\\"");
        let script = format!(
            "do shell script \"{}\" with administrator privileges",
            escaped
        );
        let status = crate::proc::hidden("osascript")
            .args(["-e", &script])
            .status()
            .map_err(|e| format!("Cannot launch the administrator prompt: {}", e))?;
        if status.success() {
            Ok(())
        } else {
            Err("Administrator permission was not granted".to_string())
        }
    }

    pub fn firewall_granted() -> bool {
        let Ok(exe) = std::env::current_exe() else {
            return false;
        };
        let path = exe.to_string_lossy().to_string();
        let output = Command::new("/usr/libexec/ApplicationFirewall/socketfilterfw")
            .args(["--getappblocked", &path])
            .output();
        match output {
            Ok(o) => {
                let text = String::from_utf8_lossy(&o.stdout).to_lowercase();
                o.status.success() && text.contains("not blocked")
            }
            Err(_) => false,
        }
    }

    pub fn firewall_detail() -> &'static str {
        "Incoming connections are allowed through the macOS application firewall"
    }
}

// ---------------------------------------------------------------------------
// Linux
// ---------------------------------------------------------------------------

#[cfg(all(unix, not(target_os = "macos")))]
mod platform {
    use super::REMOTE_PORTS;
    use std::process::Command;

    pub fn ensure_firewall() -> Result<(), String> {
        let mut rules = String::new();

        let has_ufw = Command::new("ufw")
            .arg("status")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        let has_firewalld = Command::new("firewall-cmd")
            .arg("--state")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);

        if has_ufw {
            for (port, proto) in REMOTE_PORTS {
                rules.push_str(&format!("ufw allow {}/{} comment 'Zoom VIP' || true\n", port, proto));
            }
        } else if has_firewalld {
            for (port, proto) in REMOTE_PORTS {
                rules.push_str(&format!(
                    "firewall-cmd --permanent --add-port={}/{} || true\n",
                    port, proto
                ));
            }
            rules.push_str("firewall-cmd --reload || true\n");
        } else {
            return Err(
                "No supported firewall backend found (install ufw or firewalld)".to_string(),
            );
        }

        run_admin(&rules)
    }

    fn run_admin(shell: &str) -> Result<(), String> {
        if crate::privileges::is_elevated() {
            let status = crate::proc::hidden("sh")
                .args(["-c", shell])
                .status()
                .map_err(|e| format!("Cannot run firewall command: {}", e))?;
            return if status.success() {
                Ok(())
            } else {
                Err("Firewall rules could not be applied".to_string())
            };
        }

        let has_pkexec = Command::new("pkexec")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);

        let status = if has_pkexec {
            crate::proc::hidden("pkexec")
                .args(["sh", "-c", shell])
                .status()
        } else {
            crate::proc::hidden("sudo")
                .args(["sh", "-c", shell])
                .status()
        };

        match status {
            Ok(s) if s.success() => Ok(()),
            Ok(_) => Err("Administrator permission was not granted".to_string()),
            Err(e) => Err(format!(
                "Cannot launch the elevation prompt (install pkexec or run with sudo): {}",
                e
            )),
        }
    }

    pub fn request_screen_capture() -> bool {
        true
    }

    pub fn request_accessibility() -> bool {
        true
    }

    pub fn screen_capture_granted() -> bool {
        true
    }

    pub fn screen_capture_detail() -> &'static str {
        "Linux screen capture is handled by the desktop portal"
    }

    pub fn accessibility_granted() -> bool {
        true
    }

    pub fn accessibility_detail() -> &'static str {
        "Linux input injection is handled by the X11/Wayland session"
    }

    pub fn firewall_granted() -> bool {
        let ufw = Command::new("ufw")
            .args(["status"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).contains("21114"))
            .unwrap_or(false);
        let firewalld = Command::new("firewall-cmd")
            .args(["--list-ports"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).contains("21114"))
            .unwrap_or(false);
        ufw || firewalld
    }

    pub fn firewall_detail() -> &'static str {
        "Remote access ports are allowed through the host firewall"
    }
}

// ---------------------------------------------------------------------------
// Fallback
// ---------------------------------------------------------------------------

#[cfg(not(any(windows, unix)))]
mod platform {
    pub fn ensure_firewall() -> Result<(), String> {
        Err("Firewall configuration is not supported on this platform".to_string())
    }
    pub fn request_screen_capture() -> bool {
        false
    }
    pub fn request_accessibility() -> bool {
        false
    }
    pub fn screen_capture_granted() -> bool {
        false
    }
    pub fn screen_capture_detail() -> &'static str {
        "Screen capture is not supported on this platform"
    }
    pub fn accessibility_granted() -> bool {
        false
    }
    pub fn accessibility_detail() -> &'static str {
        "Input injection is not supported on this platform"
    }
    pub fn firewall_granted() -> bool {
        false
    }
    pub fn firewall_detail() -> &'static str {
        "Firewall configuration is not supported on this platform"
    }
}

/// Directory where the Go sidecar is expected to live (used by the macOS
/// firewall grant so both binaries are allowed through).
#[allow(dead_code)]
pub fn sidecar_candidates() -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            out.push(dir.join("betterdesk-agent"));
            out.push(dir.join("betterdesk-agent.exe"));
            out.push(dir.join("Contents/MacOS/betterdesk-agent"));
        }
    }
    out
}
