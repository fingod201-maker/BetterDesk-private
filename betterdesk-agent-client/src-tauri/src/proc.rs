//! Cross-platform helper to spawn child processes **without** flashing a
//! console window.
//!
//! The desktop client is a GUI (Tauri/WebView2) process. On Windows a GUI
//! process owns no console, so every console-subsystem child it spawns
//! (`powershell.exe`, `cmd.exe`, `reg`, `sc`, the Go agent sidecar, …) would
//! otherwise allocate and *display* a brand-new console window. That is the
//! "terminal keeps popping up" behaviour the agent is supposed to avoid:
//! agents and clients must run silently in the background.
//!
//! `CREATE_NO_WINDOW` (0x08000000) creates the child with a console that is
//! never shown. On Unix the flag does not exist and the helper is a no-op.

use std::ffi::OsStr;
use std::process::Command;

/// `CREATE_NO_WINDOW` — create the child process without a visible window.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Build a [`Command`] that will not show a console window on Windows.
pub fn hidden<S: AsRef<OsStr>>(program: S) -> Command {
    let mut cmd = Command::new(program);
    hide_console(&mut cmd);
    cmd
}

/// Apply the "no visible window" creation flag to an existing [`Command`].
///
/// Use this for commands that are configured further (args, env, cwd, …).
pub fn hide_console(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}
