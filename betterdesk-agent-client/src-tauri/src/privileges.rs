//! Detection of local OS administrator privileges.
//!
//! Used to gate sensitive tray menu items (Settings, Unregister, Quit) so
//! regular users cannot disable the agent or reconfigure it without elevation.
//!
//! On Windows we check *membership* in the built-in Administrators group
//! (DOMAIN_ALIAS_RID_ADMINS) rather than requiring a UAC-elevated token.
//! This means a logged-in admin user sees the Quit/Settings options even
//! when the process was launched without "Run as Administrator".

#[cfg(windows)]
pub fn is_os_admin() -> bool {
    use windows_sys::Win32::Security::{
        AllocateAndInitializeSid, CheckTokenMembership, FreeSid,
        SECURITY_NT_AUTHORITY, SID_IDENTIFIER_AUTHORITY,
    };

    const SECURITY_BUILTIN_DOMAIN_RID: u32 = 0x00000020;
    const DOMAIN_ALIAS_RID_ADMINS: u32 = 0x00000220;

    unsafe {
        let nt_authority = SID_IDENTIFIER_AUTHORITY {
            Value: SECURITY_NT_AUTHORITY.Value,
        };
        let mut admin_group: *mut core::ffi::c_void = std::ptr::null_mut();

        let ok = AllocateAndInitializeSid(
            &nt_authority as *const _ as *const _,
            2,
            SECURITY_BUILTIN_DOMAIN_RID,
            DOMAIN_ALIAS_RID_ADMINS,
            0, 0, 0, 0, 0, 0,
            &mut admin_group,
        );
        if ok == 0 {
            return false;
        }

        let mut is_member: i32 = 0;
        let check = CheckTokenMembership(
            std::ptr::null_mut(),  // use current process token
            admin_group,
            &mut is_member,
        );

        FreeSid(admin_group);

        check != 0 && is_member != 0
    }
}

/// Whether the current process token is actually elevated (UAC).
///
/// `is_os_admin()` reports *group membership*, so a logged-in administrator
/// running a non-elevated process still returns `true`. Operations that change
/// machine-wide state (firewall rules) need this stricter check so we know
/// whether to request elevation or can run directly.
#[cfg(windows)]
pub fn is_elevated() -> bool {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::Security::{
        GetTokenInformation, TokenElevation, TOKEN_ELEVATION, TOKEN_QUERY,
    };
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    unsafe {
        let mut token = std::ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
            return false;
        }
        let mut elevation = TOKEN_ELEVATION { TokenIsElevated: 0 };
        let mut size = 0u32;
        let ok = GetTokenInformation(
            token,
            TokenElevation,
            &mut elevation as *mut _ as *mut core::ffi::c_void,
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut size,
        );
        CloseHandle(token);
        ok != 0 && elevation.TokenIsElevated != 0
    }
}

#[cfg(unix)]
pub fn is_os_admin() -> bool {
    // SAFETY: geteuid() has no preconditions and cannot fail.
    unsafe { libc::geteuid() == 0 }
}

/// On Unix, root is the only elevated state.
#[cfg(unix)]
pub fn is_elevated() -> bool {
    is_os_admin()
}

#[cfg(not(any(windows, unix)))]
pub fn is_elevated() -> bool {
    false
}

#[cfg(not(any(windows, unix)))]
pub fn is_os_admin() -> bool {
    false
}
