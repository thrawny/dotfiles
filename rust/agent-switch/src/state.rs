use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowId {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub niri_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tmux_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub agent: String,
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    pub state: String,
    pub state_updated: f64,
    pub window: WindowId,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct SessionStore {
    pub sessions: HashMap<String, Session>,
}

pub fn state_file() -> PathBuf {
    if let Ok(state_home) = env::var("XDG_STATE_HOME") {
        return PathBuf::from(state_home)
            .join("agent-switch")
            .join("sessions.json");
    }
    dirs::home_dir()
        .unwrap_or_default()
        .join(".local")
        .join("state")
        .join("agent-switch")
        .join("sessions.json")
}

pub fn load() -> SessionStore {
    let path = state_file();
    if let Ok(content) = fs::read_to_string(&path) {
        if let Ok(store) = serde_json::from_str(&content) {
            return store;
        }
    }
    SessionStore::default()
}

pub fn save(store: &SessionStore) {
    let path = state_file();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_string_pretty(store) {
        let _ = fs::write(path, json);
    }
}

pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// Get the current tmux window ID if running inside tmux
pub fn get_tmux_window_id() -> Option<String> {
    if env::var("TMUX").is_err() {
        return None;
    }
    let output = Command::new("tmux")
        .args(["display-message", "-p", "#{window_id}"])
        .output()
        .ok()?;
    if output.status.success() {
        let id = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !id.is_empty() {
            return Some(id);
        }
    }
    None
}

/// Get the focused niri window ID
pub fn get_niri_window_id() -> Option<String> {
    let output = Command::new("niri")
        .args(["msg", "-j", "focused-window"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).ok()?;
    json.get("id")
        .and_then(|v| v.as_u64())
        .map(|id| id.to_string())
}

/// Get the current window ID (prefers niri, falls back to tmux)
pub fn get_current_window_id() -> Option<(String, WindowId)> {
    // Try niri first (more common in this setup)
    if let Some(niri_id) = get_niri_window_id() {
        return Some((
            niri_id.clone(),
            WindowId {
                niri_id: Some(niri_id),
                tmux_id: None,
            },
        ));
    }

    // Fall back to tmux
    if let Some(tmux_id) = get_tmux_window_id() {
        return Some((
            tmux_id.clone(),
            WindowId {
                niri_id: None,
                tmux_id: Some(tmux_id),
            },
        ));
    }

    None
}

/// Find a session by session_id (for events that don't capture window)
#[allow(dead_code)]
pub fn find_by_session_id<'a>(
    store: &'a SessionStore,
    agent: &str,
    session_id: &str,
) -> Option<(&'a String, &'a Session)> {
    store
        .sessions
        .iter()
        .find(|(_, s)| s.agent == agent && s.session_id == session_id)
}

/// Find a session by session_id (mutable)
pub fn find_by_session_id_mut<'a>(
    store: &'a mut SessionStore,
    agent: &str,
    session_id: &str,
) -> Option<&'a mut Session> {
    store
        .sessions
        .values_mut()
        .find(|s| s.agent == agent && s.session_id == session_id)
}

/// Remove stale sessions (windows that no longer exist)
pub fn cleanup_stale(store: &mut SessionStore) {
    let valid_tmux = get_valid_tmux_windows();
    let valid_niri = get_valid_niri_windows();

    store.sessions.retain(|window_id, session| {
        if session.window.niri_id.is_some() {
            return valid_niri.contains(window_id);
        }
        if session.window.tmux_id.is_some() {
            return valid_tmux.contains(window_id);
        }
        true
    });

    // Also remove sessions older than 24h
    let cutoff = now() - 86400.0;
    store
        .sessions
        .retain(|_, session| session.state_updated > cutoff);
}

fn get_valid_tmux_windows() -> std::collections::HashSet<String> {
    let mut valid = std::collections::HashSet::new();
    if let Ok(output) = Command::new("tmux")
        .args(["list-windows", "-a", "-F", "#{window_id}"])
        .output()
    {
        if output.status.success() {
            for line in String::from_utf8_lossy(&output.stdout).lines() {
                let id = line.trim();
                if !id.is_empty() {
                    valid.insert(id.to_string());
                }
            }
        }
    }
    valid
}

fn get_valid_niri_windows() -> std::collections::HashSet<String> {
    let mut valid = std::collections::HashSet::new();
    if let Ok(output) = Command::new("niri")
        .args(["msg", "-j", "windows"])
        .output()
    {
        if output.status.success() {
            if let Ok(windows) = serde_json::from_slice::<Vec<serde_json::Value>>(&output.stdout) {
                for window in windows {
                    if let Some(id) = window.get("id").and_then(|v| v.as_u64()) {
                        valid.insert(id.to_string());
                    }
                }
            }
        }
    }
    valid
}
