//! OS-level autostart management.
//!
//! Implemented manually (no tauri-plugin-autostart dependency) so the build
//! stays on stable Tauri 2.x:
//! - Windows: `reg add/delete` on HKCU `...\Run` key
//! - macOS: `~/Library/LaunchAgents/com.betterdesk.agent.plist`
//! - Linux: `~/.config/autostart/betterdesk-agent-client.desktop`
//!
//! The app is launched with the `--autostart` CLI flag so the window stays
//! hidden on boot and only the tray icon is shown.

use log::{info, warn};

#[allow(dead_code)]
const RUN_VALUE: &str = "BetterDeskAgent";

/// Ensure the OS autostart registration matches `enabled`.
///
/// Safe to call multiple times. Logs a warning on failure but never panics.
pub fn sync_os_autostart(enabled: bool) {
    #[cfg(windows)]
    {
        let exe_path = match std::env::current_exe() {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(e) => {
                warn!("[autostart] Cannot get exe path: {}", e);
                return;
            }
        };

        if enabled {
            // `--autostart` keeps the window hidden at login: the client
            // starts in the tray only (see lib.rs). Without the flag a
            // console/UI window would pop up on every user logon.
            let launch = format!("\"{}\" --autostart", exe_path);
            let status = crate::proc::hidden("reg")
                .args([
                    "add",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    "/v",
                    RUN_VALUE,
                    "/t",
                    "REG_SZ",
                    "/d",
                    &launch,
                    "/f",
                ])
                .status();
            match status {
                Ok(s) if s.success() => info!("[autostart] Windows Run registration enabled"),
                Ok(s) => warn!("[autostart] reg add failed with exit code {:?}", s.code()),
                Err(e) => warn!("[autostart] Cannot run reg add: {}", e),
            }
        } else {
            let status = crate::proc::hidden("reg")
                .args([
                    "delete",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    "/v",
                    RUN_VALUE,
                    "/f",
                ])
                .status();
            match status {
                Ok(s) if s.success() => info!("[autostart] Windows Run registration disabled"),
                Ok(s) => warn!("[autostart] reg delete failed with exit code {:?}", s.code()),
                Err(e) => warn!("[autostart] Cannot run reg delete: {}", e),
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        let home = match std::env::var("HOME") {
            Ok(h) => h,
            Err(e) => {
                warn!("[autostart] Cannot get HOME: {}", e);
                return;
            }
        };
        let launch_agents_dir = std::path::Path::new(&home).join("Library/LaunchAgents");
        let plist_path = launch_agents_dir.join("com.betterdesk.agent.plist");

        if enabled {
            if let Err(e) = std::fs::create_dir_all(&launch_agents_dir) {
                warn!("[autostart] Cannot create LaunchAgents dir: {}", e);
                return;
            }
            let exe = std::env::current_exe()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| "zoom-private.agent".to_string());
            let plist = format!(
                r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.betterdesk.agent</string>
    <key>ProgramArguments</key><array><string>{exe}</string><string>--autostart</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>"#
            );
            if let Err(e) = std::fs::write(&plist_path, plist) {
                warn!("[autostart] Cannot write plist: {}", e);
            } else {
                info!("[autostart] macOS LaunchAgent installed");
            }
        } else {
            let _ = std::fs::remove_file(&plist_path);
            info!("[autostart] macOS LaunchAgent removed");
        }
    }

    #[cfg(target_os = "linux")]
    {
        let home = match std::env::var("HOME") {
            Ok(h) => h,
            Err(e) => {
                warn!("[autostart] Cannot get HOME: {}", e);
                return;
            }
        };
        let autostart_dir = std::path::Path::new(&home).join(".config/autostart");
        let desktop_path = autostart_dir.join("betterdesk-agent-client.desktop");

        if enabled {
            if let Err(e) = std::fs::create_dir_all(&autostart_dir) {
                warn!("[autostart] Cannot create autostart dir: {}", e);
                return;
            }
            let exe = std::env::current_exe()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| "betterdesk-agent-client".to_string());
            let desktop = format!(
                "[Desktop Entry]\nType=Application\nName=zoom-private.agent\nExec={} --autostart\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\n",
                exe
            );
            if let Err(e) = std::fs::write(&desktop_path, desktop) {
                warn!("[autostart] Cannot write desktop file: {}", e);
            } else {
                info!("[autostart] Linux .desktop installed");
            }
        } else {
            let _ = std::fs::remove_file(&desktop_path);
            info!("[autostart] Linux .desktop removed");
        }
    }

    #[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
    {
        let _ = enabled;
        warn!("[autostart] Platform not supported for autostart");
    }
}
