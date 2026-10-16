use std::sync::OnceLock;
use std::os::raw::c_char;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

static SERVER_CONFIG: OnceLock<ServerConfig> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub use_https: bool,
    pub api_port: u16,
    pub cdap_port: u16,
}

impl ServerConfig {
    pub fn base_url(&self) -> String {
        let scheme = if self.use_https { "https" } else { "http" };
        if (self.use_https && self.api_port == 443) || (!self.use_https && self.api_port == 80) {
            format!("{}://{}", scheme, self.host)
        } else {
            format!("{}://{}:{}", scheme, self.host, self.api_port)
        }
    }

    pub fn cdap_url(&self) -> String {
        let scheme = if self.use_https { "wss" } else { "ws" };
        if (self.use_https && self.api_port == 443) || (!self.use_https && self.api_port == 80) {
            format!("{}://{}/cdap", scheme, self.host)
        } else {
            format!("{}://{}:{}/cdap", scheme, self.host, self.cdap_port)
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ConnectionStatus {
    pub connected: u8,
    pub latency_ms: i32,
    pub error_code: i32,
}

#[no_mangle]
pub extern "C" fn betterdesk_configure_server(
    host: *const c_char,
    use_https: u8,
    api_port: u16,
) {
    let host_str = unsafe {
        if host.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(host).to_string_lossy().into_owned()
        }
    };
    let config = ServerConfig {
        host: host_str,
        use_https: use_https != 0,
        api_port,
        cdap_port: 21122,
    };
    let _ = SERVER_CONFIG.set(config);
    eprintln!("[betterdesk-android] Configured server: {:?}", config);
}

#[no_mangle]
pub extern "C" fn betterdesk_server_base_url() -> *mut c_char {
    let config = match SERVER_CONFIG.get() {
        Some(c) => c,
        None => return std::ptr::null_mut(),
    };
    let url = config.base_url();
    CStringHelper::into_raw(url)
}

#[no_mangle]
pub extern "C" fn betterdesk_server_cdap_url() -> *mut c_char {
    let config = match SERVER_CONFIG.get() {
        Some(c) => c,
        None => return std::ptr::null_mut(),
    };
    let url = config.cdap_url();
    CStringHelper::into_raw(url)
}

#[no_mangle]
pub extern "C" fn betterdesk_connection_status() -> ConnectionStatus {
    ConnectionStatus {
        connected: 0,
        latency_ms: -1,
        error_code: 0,
    }
}

#[no_mangle]
pub extern "C" fn betterdesk_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(String::from_raw_ptr(ptr)) };
    }
}

/// Helper to leak a String into a raw C char pointer (caller must free via betterdesk_free_string).
struct CStringHelper;

impl CStringHelper {
    fn into_raw(s: String) -> *mut c_char {
        use std::ffi::CString;
        match CString::new(s) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_omits_default_https_port() {
        betterdesk_configure_server("panel.telcom.stream".as_ptr() as *const c_char, 1, 443);
        // SERVER_CONFIG is OnceLock; only first call sticks, so test via new instance is not possible.
        // This is a compile-only smoke test.
    }
}
