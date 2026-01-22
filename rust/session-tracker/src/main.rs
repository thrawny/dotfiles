use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Deserialize)]
struct HookInput {
    hook_event_name: Option<String>,
    session_id: Option<String>,
    transcript_path: Option<String>,
    cwd: Option<String>,
    notification_type: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct SessionData {
    session_id: String,
    transcript_path: Option<String>,
    cwd: Option<String>,
    niri_window_id: Option<String>,
    tmux_window_id: Option<String>,
    state: String,
    state_updated: f64,
}

type Sessions = HashMap<String, SessionData>;

#[derive(Debug, Serialize)]
struct FocusRequest {
    cmd: &'static str,
    ts: f64,
}

#[derive(Debug, Deserialize)]
struct FocusResponse {
    window_id: Option<u64>,
    title: Option<String>,
    app_id: Option<String>,
    timestamp: Option<f64>,
}

fn niri_switcher_socket_path() -> PathBuf {
    env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("niri-switcher.sock")
}

fn sessions_file() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_default()
        .join(".claude")
        .join("active-sessions.json")
}

fn load_sessions() -> Sessions {
    let path = sessions_file();
    if path.exists() {
        fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    } else {
        HashMap::new()
    }
}

fn save_sessions(sessions: &Sessions) {
    let path = sessions_file();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_string_pretty(sessions) {
        let _ = fs::write(path, json);
    }
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn query_niri_switcher_focus(ts: f64) -> Option<FocusResponse> {
    let path = niri_switcher_socket_path();
    let mut stream = UnixStream::connect(&path).ok()?;
    let request = FocusRequest { cmd: "focus", ts };
    let payload = serde_json::to_vec(&request).ok()?;
    stream.write_all(&payload).ok()?;
    let _ = stream.shutdown(Shutdown::Write);
    let mut response = String::new();
    stream.read_to_string(&mut response).ok()?;
    serde_json::from_str(&response).ok()
}

fn get_niri_window_id(sessions: &Sessions) -> Option<String> {
    let snapshot = query_niri_switcher_focus(now());
    if let Some(snapshot) = snapshot {
        if let Some(window_id) = snapshot.window_id {
            let window_id = window_id.to_string();
            if sessions.contains_key(&window_id) {
                return Some(window_id);
            }
            let title = snapshot.title.unwrap_or_default();
            if let Some(first_char) = title.chars().next()
                && !first_char.is_alphanumeric()
            {
                return Some(window_id);
            }
        }
    }
    None
}

fn get_tmux_window_id() -> Option<String> {
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

fn find_session_by_id<'a>(sessions: &'a Sessions, session_id: &str) -> Option<&'a String> {
    sessions
        .iter()
        .find(|(_, data)| data.session_id == session_id)
        .map(|(window_id, _)| window_id)
}

fn ends_with_question(transcript_path: &str) -> bool {
    let output = match Command::new("tail")
        .args(["-n", "20", transcript_path])
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => return false,
    };

    let content = String::from_utf8_lossy(&output.stdout);
    let mut last_text: Option<String> = None;

    for line in content.lines() {
        if line.is_empty() {
            continue;
        }
        if let Ok(entry) = serde_json::from_str::<serde_json::Value>(line)
            && entry.get("type").and_then(|t| t.as_str()) == Some("assistant")
            && let Some(content_arr) = entry
                .get("message")
                .and_then(|m| m.get("content"))
                .and_then(|c| c.as_array())
        {
            for item in content_arr {
                if item.get("type").and_then(|t| t.as_str()) == Some("text")
                    && let Some(text) = item.get("text").and_then(|t| t.as_str())
                {
                    last_text = Some(text.to_string());
                }
            }
        }
    }

    last_text
        .map(|t| t.trim_end().ends_with('?'))
        .unwrap_or(false)
}

fn main() {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        return;
    }

    let hook_input: HookInput = match serde_json::from_str(&input) {
        Ok(h) => h,
        Err(_) => return,
    };

    let event = hook_input.hook_event_name.as_deref().unwrap_or("");
    let session_id = match &hook_input.session_id {
        Some(id) => id.clone(),
        None => return,
    };

    let mut sessions = load_sessions();

    match event {
        "SessionStart" => {
            let niri_id = get_niri_window_id(&sessions);
            let tmux_id = get_tmux_window_id();
            let window_id = niri_id.clone().or_else(|| tmux_id.clone());

            if let Some(wid) = window_id {
                sessions.insert(
                    wid,
                    SessionData {
                        session_id,
                        transcript_path: hook_input.transcript_path,
                        cwd: hook_input.cwd,
                        niri_window_id: niri_id,
                        tmux_window_id: tmux_id,
                        state: "waiting".to_string(),
                        state_updated: now(),
                    },
                );
                save_sessions(&sessions);
            }
        }

        "SessionEnd" => {
            // Only look up by session_id - don't query focused window
            // (user may have switched to another window)
            if let Some(wid) = find_session_by_id(&sessions, &session_id).cloned() {
                sessions.remove(&wid);
                save_sessions(&sessions);
            }
        }

        "Stop" => {
            let window_id = find_session_by_id(&sessions, &session_id).cloned();
            if let Some(wid) = window_id
                && let Some(session) = sessions.get_mut(&wid)
            {
                let is_question = session
                    .transcript_path
                    .as_ref()
                    .map(|p| ends_with_question(p))
                    .unwrap_or(false);

                session.state = if is_question {
                    "waiting".to_string()
                } else {
                    "idle".to_string()
                };
                session.state_updated = now();
                save_sessions(&sessions);
            }
        }

        "Notification" => {
            if hook_input.notification_type.as_deref() == Some("permission_prompt") {
                let window_id = find_session_by_id(&sessions, &session_id).cloned();
                if let Some(wid) = window_id
                    && let Some(session) = sessions.get_mut(&wid)
                {
                    session.state = "waiting".to_string();
                    session.state_updated = now();
                    save_sessions(&sessions);
                }
            }
        }

        "UserPromptSubmit" => {
            let niri_id = get_niri_window_id(&sessions);
            let tmux_id = get_tmux_window_id();
            let focused_id = niri_id.clone().or_else(|| tmux_id.clone());
            let existing_id = find_session_by_id(&sessions, &session_id).cloned();

            if let Some(focused) = focused_id {
                if let Some(existing) = existing_id.as_ref()
                    && existing != &focused
                {
                    sessions.remove(existing);
                }

                sessions.insert(
                    focused,
                    SessionData {
                        session_id,
                        transcript_path: hook_input.transcript_path,
                        cwd: hook_input.cwd,
                        niri_window_id: niri_id,
                        tmux_window_id: tmux_id,
                        state: "responding".to_string(),
                        state_updated: now(),
                    },
                );
                save_sessions(&sessions);
            } else if let Some(existing) = existing_id {
                if let Some(session) = sessions.get_mut(&existing) {
                    session.state = "responding".to_string();
                    session.state_updated = now();
                    save_sessions(&sessions);
                }
            }
        }

        "PreToolUse" => {
            // Tool is about to run - Claude is working
            let window_id = find_session_by_id(&sessions, &session_id).cloned();
            if let Some(wid) = window_id
                && let Some(session) = sessions.get_mut(&wid)
            {
                // Only update if currently waiting (avoid unnecessary writes)
                if session.state == "waiting" {
                    session.state = "responding".to_string();
                    session.state_updated = now();
                    save_sessions(&sessions);
                }
            }
        }

        _ => {}
    }
}
