// Show console window only when --console flag is NOT present.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(windows)]
fn attach_parent_console() {
    unsafe {
        windows_sys::Win32::System::Console::AttachConsole(
            windows_sys::Win32::System::Console::ATTACH_PARENT_PROCESS,
        );
    }
}

#[cfg(not(windows))]
fn attach_parent_console() {}

fn print_version() {
    let text = format!(
        "{} {}\n",
        env!("CARGO_PKG_NAME"),
        env!("CARGO_PKG_VERSION")
    );

    use std::io::Write;

    #[cfg(windows)]
    {
        use windows_sys::Win32::Storage::FileSystem::{
            GetFileType, WriteFile, FILE_TYPE_DISK, FILE_TYPE_PIPE,
        };
        use windows_sys::Win32::System::Console::{GetStdHandle, STD_OUTPUT_HANDLE};

        // A windows_subsystem binary has no console, but a redirected stdout
        // pipe/disk handle from the calling shell is valid; write to it.
        unsafe {
            let handle = GetStdHandle(STD_OUTPUT_HANDLE);
            let kind = GetFileType(handle);
            if kind == FILE_TYPE_PIPE || kind == FILE_TYPE_DISK {
                let mut written = 0u32;
                if WriteFile(
                    handle,
                    text.as_ptr(),
                    text.len() as u32,
                    &mut written,
                    std::ptr::null_mut(),
                ) != 0
                {
                    return;
                }
            }
        }

        attach_parent_console();
        if let Ok(mut out) = std::fs::OpenOptions::new().write(true).open("CONOUT$") {
            let _ = out.write_all(text.as_bytes());
            let _ = out.flush();
            return;
        }
        return;
    }

    #[cfg(not(windows))]
    {
        let mut stdout = std::io::stdout();
        let _ = stdout.write_all(text.as_bytes());
        let _ = stdout.flush();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // `--version` must be a CLI-only probe: print and exit instead of
    // launching the full GUI agent.
    if args.iter().any(|a| a == "--version" || a == "-V") {
        print_version();
        return;
    }

    #[cfg(all(windows, not(debug_assertions)))]
    if args.iter().any(|a| a == "--console") {
        attach_parent_console();
    }

    betterdesk_agent_client_lib::run();
}
