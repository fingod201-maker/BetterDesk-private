use std::sync::{Arc, OnceLock, RwLock};
use std::os::raw::c_char;
use std::thread;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::{broadcast, Mutex};

static SERVER_CONFIG: OnceLock<ServerConfig> = OnceLock::new();
static PERMANENT_PASSWORD_HASH: OnceLock<RwLock<Option<String>>> = OnceLock::new();
static UNATTENDED_ENABLED: OnceLock<RwLock<bool>> = OnceLock::new();

/// Broadcast channel for screen frames to connected operators.
static FRAME_BROADCAST: OnceLock<broadcast::Sender<Vec<u8>>> = OnceLock::new();

/// Connected client count.
static CLIENT_COUNT: OnceLock<Mutex<usize>> = OnceLock::new();

/// Tokio runtime handle for the listener.
static LISTENER_RUNTIME: OnceLock<Mutex<Option<tokio::runtime::Runtime>>> = OnceLock::new();

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

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct UnattendedConfig {
    pub enabled: u8,
    pub port: u16,
    pub has_password: u8,
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

fn get_password_lock() -> &'static RwLock<Option<String>> {
    PERMANENT_PASSWORD_HASH.get_or_init(|| RwLock::new(None))
}

fn get_enabled_lock() -> &'static RwLock<bool> {
    UNATTENDED_ENABLED.get_or_init(|| RwLock::new(false))
}

#[no_mangle]
pub extern "C" fn betterdesk_set_permanent_password(
    password: *const c_char,
) {
    let pw = unsafe {
        if password.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(password).to_string_lossy().into_owned()
        }
    };

    let enabled_lock = get_enabled_lock();
    let pw_lock = get_password_lock();

    if pw.is_empty() {
        *enabled_lock.write().unwrap() = false;
        *pw_lock.write().unwrap() = None;
        eprintln!("[betterdesk-android] Permanent password cleared");
        return;
    }

    let salt: [u8; 16] = {
        let mut s = [0u8; 16];
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        for (i, b) in s.iter_mut().enumerate().take(16) {
            *b = ((n >> (i * 4)) & 0xFF) as u8;
        }
        s
    };

    let hash = pbkdf2_hash(&pw, &salt);
    *enabled_lock.write().unwrap() = true;
    *pw_lock.write().unwrap() = Some(format!("{}:{}", hex_encode(&salt), hash));
    eprintln!("[betterdesk-android] Permanent password set");
}

#[no_mangle]
pub extern "C" fn betterdesk_verify_password(
    candidate: *const c_char,
) -> u8 {
    let cand = unsafe {
        if candidate.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(candidate).to_string_lossy().into_owned()
        }
    };

    let enabled = *get_enabled_lock().read().unwrap();
    if !enabled { return 0; }

    let stored = get_password_lock().read().unwrap();
    let stored = match stored.as_ref() {
        Some(s) => s,
        None => return 0,
    };

    let parts: Vec<&str> = stored.splitn(2, ':').collect();
    if parts.len() != 2 { return 0; }

    let salt = match hex_decode(parts[0]) {
        Some(s) => s,
        None => return 0,
    };
    let expected_hash = parts[1];

    let candidate_hash = pbkdf2_hash(&cand, &salt);
    if candidate_hash == expected_hash { 1 } else { 0 }
}

#[no_mangle]
pub extern "C" fn betterdesk_unattended_config() -> UnattendedConfig {
    let enabled = *get_enabled_lock().read().unwrap();
    let has_password = get_password_lock().read().unwrap().is_some();
    UnattendedConfig {
        enabled: if enabled { 1 } else { 0 },
        port: 21122,
        has_password: if has_password { 1 } else { 0 },
    }
}

#[no_mangle]
pub extern "C" fn betterdesk_start_listener() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (tx, _) = broadcast::channel::<Vec<u8>>(16);
    let _ = FRAME_BROADCAST.set(tx);
    let _ = CLIENT_COUNT.set(Mutex::new(0));

    rt.spawn(async move {
        let listener = match TcpListener::bind("0.0.0.0:21122").await {
            Ok(l) => l,
            Err(e) => {
                eprintln!("[betterdesk-android] Failed to bind port 21122: {}", e);
                return;
            }
        };
        eprintln!("[betterdesk-android] TCP listener active on port 21122");

        loop {
            match listener.accept().await {
                Ok((socket, addr)) => {
                    eprintln!("[betterdesk-android] Connection from {}", addr);
                    let mut rx = FRAME_BROADCAST
                        .get()
                        .expect("frame broadcast")
                        .subscribe();
                    let client_count = CLIENT_COUNT
                        .get()
                        .expect("client count")
                        .clone();
                    tokio::spawn(async move {
                        let _guard = client_count.lock().await;
                        drop(_guard);
                        let _ = rx.recv().await;
                    });
                }
                Err(e) => {
                    eprintln!("[betterdesk-android] Accept error: {}", e);
                }
            }
        }
    });

    let _ = LISTENER_RUNTIME.set(Mutex::new(Some(rt)));
    eprintln!("[betterdesk-android] Listener runtime started");
}

#[no_mangle]
pub extern "C" fn betterdesk_stop_listener() {
    if let Some(rt) = LISTENER_RUNTIME.get().map(|m| m.lock().unwrap()).flatten() {
        drop(rt);
    }
    eprintln!("[betterdesk-android] Listener stopped");
}

#[no_mangle]
pub extern "C" fn betterdesk_capture_frame() -> *mut c_char {
    let json = r#"{"frame":null,"width":0,"height":0}"#;
    CStringHelper::into_raw(json.to_string())
}

#[no_mangle]
pub extern "C" fn betterdesk_inject_touch(
    x: f64,
    y: f64,
    down: u8,
) {
    eprintln!("[betterdesk-android] Inject touch: x={}, y={}, down={}", x, y, down);
}

#[no_mangle]
pub extern "C" fn betterdesk_inject_key(
    key_code: i32,
    down: u8,
) {
    eprintln!("[betterdesk-android] Inject key: code={}, down={}", key_code, down);
}

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

fn pbkdf2_hash(password: &str, salt: &[u8]) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    password.hash(&mut hasher);
    salt.hash(&mut hasher);
    format!("{:064x}", hasher.finish())
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_omits_default_https_port() {
        betterdesk_configure_server("panel.telcom.stream".as_ptr() as *const c_char, 1, 443);
    }

    #[test]
    fn password_set_and_verify() {
        betterdesk_set_permanent_password("operator123".as_ptr() as *const c_char);
        assert_eq!(betterdesk_verify_password("operator123".as_ptr() as *const c_char), 1);
        assert_eq!(betterdesk_verify_password("wrong".as_ptr() as *const c_char), 0);
        betterdesk_set_permanent_password(std::ptr::null_mut());
        assert_eq!(betterdesk_verify_password("operator123".as_ptr() as *const c_char), 0);
    }
}
