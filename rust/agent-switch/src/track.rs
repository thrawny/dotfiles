use crate::daemon;
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::process::Command;

#[derive(Debug, Deserialize)]
struct HookInput {
    session_id: Option<String>,
    agent: Option<String>,
    cwd: Option<String>,
    transcript_path: Option<String>,
    notification_type: Option<String>,
}

#[derive(Debug, Serialize)]
struct TrackMessage {
    event: String,
    session_id: String,
    agent: Option<String>,
    cwd: Option<String>,
    transcript_path: Option<String>,
    notification_type: Option<String>,
    tmux_id: Option<String>,
}

fn get_tmux_window_id() -> Option<String> {
    if std::env::var("TMUX").is_err() {
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

/// Returns true on success, false on failure
pub fn handle_event(event: &str) -> bool {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        eprintln!("Failed to read stdin");
        return false;
    }

    let hook: HookInput = match serde_json::from_str(&input) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("Failed to parse hook input: {}", e);
            return false;
        }
    };

    let session_id = match hook.session_id {
        Some(id) => id,
        None => {
            eprintln!("Missing session_id");
            return false;
        }
    };

    let msg = TrackMessage {
        event: event.to_string(),
        session_id,
        agent: hook.agent,
        cwd: hook.cwd,
        transcript_path: hook.transcript_path,
        notification_type: hook.notification_type,
        tmux_id: get_tmux_window_id(),
    };

    let json = match serde_json::to_string(&msg) {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to serialize message: {}", e);
            return false;
        }
    };

    let mut stream = match UnixStream::connect(daemon::socket_path()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Daemon not running: {}", e);
            return false;
        }
    };

    let cmd = format!("track {}", json);
    if let Err(e) = stream.write_all(cmd.as_bytes()) {
        eprintln!("Failed to send command: {}", e);
        return false;
    }

    let mut response = [0u8; 64];
    match stream.read(&mut response) {
        Ok(n) if n > 0 => {
            let resp = String::from_utf8_lossy(&response[..n]);
            if resp.trim() == "ok" {
                true
            } else {
                eprintln!("Daemon error: {}", resp.trim());
                false
            }
        }
        Ok(_) => {
            eprintln!("Empty response from daemon");
            false
        }
        Err(e) => {
            eprintln!("Failed to read response: {}", e);
            false
        }
    }
}
