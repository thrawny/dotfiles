use crate::state::{self, Session, SessionStore};
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct HookInput {
    agent: Option<String>,
    session_id: Option<String>,
    cwd: Option<String>,
    transcript_path: Option<String>,
    notification_type: Option<String>,
    hook_event_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct TrackMessage {
    event: String,
    agent: Option<String>,
    session_id: String,
    cwd: Option<String>,
    transcript_path: Option<String>,
    notification_type: Option<String>,
}

fn socket_path() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("agent-switch.sock")
}

fn send_to_daemon(event: &str, hook: &HookInput, session_id: &str) -> bool {
    let msg = TrackMessage {
        event: event.to_string(),
        agent: hook.agent.clone(),
        session_id: session_id.to_string(),
        cwd: hook.cwd.clone(),
        transcript_path: hook.transcript_path.clone(),
        notification_type: hook.notification_type.clone(),
    };

    let json = match serde_json::to_string(&msg) {
        Ok(j) => j,
        Err(_) => return false,
    };

    let mut stream = match UnixStream::connect(socket_path()) {
        Ok(s) => s,
        Err(_) => return false,
    };

    let cmd = format!("track {}", json);
    if stream.write_all(cmd.as_bytes()).is_err() {
        return false;
    }

    let mut response = [0u8; 64];
    match stream.read(&mut response) {
        Ok(n) if n > 0 => {
            let resp = String::from_utf8_lossy(&response[..n]);
            resp.trim() == "ok"
        }
        _ => false,
    }
}

pub fn handle_event(event: &str) {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        return;
    }

    let hook: HookInput = match serde_json::from_str(&input) {
        Ok(h) => h,
        Err(_) => return,
    };

    let session_id = match &hook.session_id {
        Some(id) => id.clone(),
        None => return,
    };

    // Inside tmux: use direct handling to capture tmux window ID
    // Outside tmux: try daemon first for niri focus tracking
    let in_tmux = std::env::var("TMUX").is_ok();

    if !in_tmux && send_to_daemon(event, &hook, &session_id) {
        return;
    }

    // Direct state manipulation (tmux or daemon not running)
    handle_event_direct(event, &hook, &session_id);
}

fn handle_event_direct(event: &str, hook: &HookInput, session_id: &str) {
    let agent = hook.agent.as_deref().unwrap_or("claude");
    let mut store = state::load();

    match event {
        "session-start" => handle_session_start(&mut store, agent, session_id, hook),
        "session-end" => handle_session_end(&mut store, agent, session_id),
        "prompt-submit" => handle_prompt_submit(&mut store, agent, session_id, hook),
        "stop" => handle_stop(&mut store, agent, session_id, hook),
        "notification" => handle_notification(&mut store, agent, session_id, hook),
        _ => {}
    }

    state::save(&store);
}

fn handle_session_start(store: &mut SessionStore, agent: &str, session_id: &str, hook: &HookInput) {
    let Some((window_key, window_id)) = state::get_current_window_id() else {
        return;
    };

    let session = Session {
        agent: agent.to_string(),
        session_id: session_id.to_string(),
        cwd: hook.cwd.clone(),
        state: "waiting".to_string(),
        state_updated: state::now(),
        window: window_id,
    };

    store.sessions.insert(window_key, session);
}

fn handle_session_end(store: &mut SessionStore, agent: &str, session_id: &str) {
    let key_to_remove = store
        .sessions
        .iter()
        .find(|(_, s)| s.agent == agent && s.session_id == session_id)
        .map(|(k, _)| k.clone());

    if let Some(key) = key_to_remove {
        store.sessions.remove(&key);
    }
}

fn handle_prompt_submit(store: &mut SessionStore, agent: &str, session_id: &str, hook: &HookInput) {
    // Update window IDs on every prompt (they may have changed or been missing)
    let window_update = state::get_current_window_id();

    if let Some(session) = state::find_by_session_id_mut(store, agent, session_id) {
        session.state = "responding".to_string();
        session.state_updated = state::now();
        // Update window IDs if we got them (preserves existing if not)
        if let Some((_, window_id)) = window_update {
            session.window = window_id;
        }
        return;
    }

    let Some((window_key, window_id)) = window_update else {
        return;
    };

    let session = Session {
        agent: agent.to_string(),
        session_id: session_id.to_string(),
        cwd: hook.cwd.clone(),
        state: "responding".to_string(),
        state_updated: state::now(),
        window: window_id,
    };

    store.sessions.insert(window_key, session);
}

fn handle_stop(store: &mut SessionStore, agent: &str, session_id: &str, hook: &HookInput) {
    let Some(session) = state::find_by_session_id_mut(store, agent, session_id) else {
        return;
    };

    let is_question = hook
        .transcript_path
        .as_ref()
        .map(|p| ends_with_question(p))
        .unwrap_or(false);

    session.state = if is_question {
        "waiting".to_string()
    } else {
        "idle".to_string()
    };
    session.state_updated = state::now();
}

fn handle_notification(store: &mut SessionStore, agent: &str, session_id: &str, hook: &HookInput) {
    if hook.notification_type.as_deref() != Some("permission_prompt") {
        return;
    }

    let Some(session) = state::find_by_session_id_mut(store, agent, session_id) else {
        return;
    };

    session.state = "waiting".to_string();
    session.state_updated = state::now();
}

fn ends_with_question(transcript_path: &str) -> bool {
    use std::process::Command;

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
        if let Ok(entry) = serde_json::from_str::<serde_json::Value>(line) {
            if entry.get("type").and_then(|t| t.as_str()) != Some("assistant") {
                continue;
            }
            if let Some(content_arr) = entry
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
    }

    last_text
        .map(|t| t.trim_end().ends_with('?'))
        .unwrap_or(false)
}
