use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
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
struct SessionEntry {
    session_id: String,
    source: String,
    transcript_path: Option<String>,
    cwd: Option<String>,
    niri_window_id: Option<String>,
    tmux_window_id: Option<String>,
    state: String,
    state_updated: f64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct SessionStore {
    version: u32,
    sessions: Vec<SessionEntry>,
}

impl Default for SessionStore {
    fn default() -> Self {
        Self {
            version: 1,
            sessions: Vec::new(),
        }
    }
}

#[derive(Debug, Serialize)]
struct FocusRequest {
    cmd: &'static str,
    ts: f64,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct FocusResponse {
    window_id: Option<u64>,
    title: Option<String>,
    app_id: Option<String>,
    timestamp: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct CodexRecord {
    #[serde(rename = "type")]
    record_type: String,
    payload: serde_json::Value,
}

#[derive(Debug, Default, Clone)]
struct CodexFileState {
    offset: u64,
    session_id: Option<String>,
    cwd: Option<String>,
}

fn niri_switcher_socket_path() -> PathBuf {
    env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("niri-switcher.sock")
}

fn sessions_file() -> PathBuf {
    if let Ok(cache_home) = env::var("XDG_CACHE_HOME") {
        return PathBuf::from(cache_home).join("active-sessions.json");
    }
    dirs::home_dir()
        .unwrap_or_default()
        .join(".cache")
        .join("active-sessions.json")
}

fn legacy_sessions_file() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_default()
        .join(".claude")
        .join("active-sessions.json")
}

fn load_sessions() -> SessionStore {
    let path = sessions_file();
    if path.exists()
        && let Ok(content) = fs::read_to_string(&path)
            && let Ok(store) = serde_json::from_str::<SessionStore>(&content)
        {
            return store;
        }

    let legacy_path = legacy_sessions_file();
    if legacy_path.exists()
        && let Ok(content) = fs::read_to_string(&legacy_path)
            && let Ok(legacy) = serde_json::from_str::<HashMap<String, LegacySession>>(&content)
        {
            let sessions = legacy
                .into_iter()
                .map(|(window_id, entry)| entry.into_session(window_id))
                .collect();
            return SessionStore {
                version: 1,
                sessions,
            };
        }

    SessionStore::default()
}

fn save_sessions(store: &SessionStore) {
    let path = sessions_file();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_string_pretty(store) {
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

fn is_known_niri_window(store: &SessionStore, window_id: &str) -> bool {
    store
        .sessions
        .iter()
        .any(|session| session.niri_window_id.as_deref() == Some(window_id))
}

fn get_niri_window_id(store: &SessionStore) -> Option<String> {
    let snapshot = query_niri_switcher_focus(now());
    if let Some(snapshot) = snapshot {
        if let Some(window_id) = snapshot.window_id {
            let window_id = window_id.to_string();
            if is_known_niri_window(store, &window_id) {
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

fn find_session_index(store: &SessionStore, source: &str, session_id: &str) -> Option<usize> {
    store
        .sessions
        .iter()
        .position(|entry| entry.source == source && entry.session_id == session_id)
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

fn upsert_claude_session(
    store: &mut SessionStore,
    session_id: String,
    transcript_path: Option<String>,
    cwd: Option<String>,
    niri_window_id: Option<String>,
    tmux_window_id: Option<String>,
    state: &str,
) {
    let entry = SessionEntry {
        session_id: session_id.clone(),
        source: "claude".to_string(),
        transcript_path,
        cwd,
        niri_window_id,
        tmux_window_id,
        state: state.to_string(),
        state_updated: now(),
    };

    if let Some(index) = find_session_index(store, "claude", &session_id) {
        store.sessions[index] = entry;
    } else {
        store.sessions.push(entry);
    }
}

fn update_claude_state(store: &mut SessionStore, session_id: &str, state: &str) {
    if let Some(index) = find_session_index(store, "claude", session_id) {
        store.sessions[index].state = state.to_string();
        store.sessions[index].state_updated = now();
    }
}

fn remove_claude_session(store: &mut SessionStore, session_id: &str) {
    store
        .sessions
        .retain(|entry| !(entry.source == "claude" && entry.session_id == session_id));
}

fn update_codex_session(
    store: &mut SessionStore,
    session_id: &str,
    cwd: Option<&str>,
    state: &str,
) {
    if let Some(index) = find_session_index(store, "codex", session_id) {
        if store.sessions[index].cwd.is_none() {
            store.sessions[index].cwd = cwd.map(|value| value.to_string());
        }
        store.sessions[index].state = state.to_string();
        store.sessions[index].state_updated = now();
        return;
    }

    store.sessions.push(SessionEntry {
        session_id: session_id.to_string(),
        source: "codex".to_string(),
        transcript_path: None,
        cwd: cwd.map(|value| value.to_string()),
        niri_window_id: None,
        tmux_window_id: None,
        state: state.to_string(),
        state_updated: now(),
    });
}

fn handle_codex_record(
    store: &mut SessionStore,
    record: CodexRecord,
    fallback_session_id: Option<&str>,
    fallback_cwd: Option<&str>,
) {
    match record.record_type.as_str() {
        "session_meta" => {
            let session_id = record
                .payload
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if session_id.is_empty() {
                return;
            }
            let cwd = record
                .payload
                .get("cwd")
                .and_then(|v| v.as_str())
                .or(fallback_cwd);
            update_codex_session(store, session_id, cwd, "idle");
        }
        "event_msg" => {
            let event_type = record
                .payload
                .get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let session_id = record
                .payload
                .get("session_id")
                .and_then(|v| v.as_str())
                .or(fallback_session_id)
                .unwrap_or("");
            if session_id.is_empty() {
                return;
            }
            match event_type {
                "user_message" => {
                    update_codex_session(store, session_id, fallback_cwd, "responding");
                }
                "agent_message" => update_codex_session(store, session_id, fallback_cwd, "idle"),
                _ => {}
            }
        }
        "response_item" => {
            let role = record
                .payload
                .get("role")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let session_id = record
                .payload
                .get("session_id")
                .and_then(|v| v.as_str())
                .or(fallback_session_id)
                .unwrap_or("");
            if session_id.is_empty() {
                return;
            }
            if role == "assistant" {
                update_codex_session(store, session_id, fallback_cwd, "responding");
            }
        }
        _ => {}
    }
}

fn is_codex_rollout_file(path: &Path) -> bool {
    let filename = match path.file_name().and_then(|name| name.to_str()) {
        Some(name) => name,
        None => return false,
    };
    filename.starts_with("rollout-") && filename.ends_with(".jsonl")
}

fn process_codex_file(
    path: &Path,
    states: &mut HashMap<PathBuf, CodexFileState>,
    store: &mut SessionStore,
) {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return,
    };

    let state = states.entry(path.to_path_buf()).or_default();
    let mut offset = state.offset;
    let len = match file.metadata() {
        Ok(meta) => meta.len(),
        Err(_) => return,
    };
    if len < offset {
        offset = 0;
        state.session_id = None;
        state.cwd = None;
    }

    if file.seek(SeekFrom::Start(offset)).is_err() {
        return;
    }

    let mut reader = BufReader::new(file);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Ok(record) = serde_json::from_str::<CodexRecord>(trimmed) {
                    if record.record_type == "session_meta" {
                        if let Some(session_id) = record.payload.get("id").and_then(|v| v.as_str()) {
                            state.session_id = Some(session_id.to_string());
                        }
                        if let Some(cwd) = record.payload.get("cwd").and_then(|v| v.as_str()) {
                            state.cwd = Some(cwd.to_string());
                        }
                    }
                    handle_codex_record(
                        store,
                        record,
                        state.session_id.as_deref(),
                        state.cwd.as_deref(),
                    );
                }
            }
            Err(_) => break,
        }
    }

    state.offset = len;
}

fn walk_codex_files(dir: &Path, files: &mut Vec<PathBuf>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk_codex_files(&path, files);
            } else if is_codex_rollout_file(&path) {
                files.push(path);
            }
        }
    }
}

fn codex_sessions_root() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_default()
        .join(".codex")
        .join("sessions")
}

fn run_codex_watcher() {
    let (tx, rx) = mpsc::channel();

    let mut watcher = match RecommendedWatcher::new(
        move |res: Result<notify::Event, notify::Error>| {
            let _ = tx.send(res);
        },
        notify::Config::default(),
    ) {
        Ok(watcher) => watcher,
        Err(err) => {
            eprintln!("Failed to start Codex watcher: {err}");
            return;
        }
    };

    let sessions_root = codex_sessions_root();
    if watcher
        .watch(&sessions_root, RecursiveMode::Recursive)
        .is_err()
    {
        eprintln!("Failed to watch {sessions_root:?}");
        return;
    }

    let mut states: HashMap<PathBuf, CodexFileState> = HashMap::new();
    let mut files = Vec::new();
    walk_codex_files(&sessions_root, &mut files);
    let mut store = load_sessions();
    for file in files {
        process_codex_file(&file, &mut states, &mut store);
    }
    save_sessions(&store);

    loop {
        let event = match rx.recv() {
            Ok(Ok(event)) => event,
            Ok(Err(_)) => continue,
            Err(_) => break,
        };

        let mut store = load_sessions();
        let mut changed = false;
        for path in event.paths {
            if !is_codex_rollout_file(&path) {
                continue;
            }
            process_codex_file(&path, &mut states, &mut store);
            changed = true;
        }
        if changed {
            save_sessions(&store);
        }
    }
}

fn should_run_codex_watcher() -> bool {
    env::args().any(|arg| arg == "--watch-codex")
}

fn main() {
    if should_run_codex_watcher() {
        run_codex_watcher();
        return;
    }

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

    let mut store = load_sessions();

    match event {
        "SessionStart" => {
            let niri_id = get_niri_window_id(&store);
            let tmux_id = get_tmux_window_id();
            let window_id = niri_id.clone().or_else(|| tmux_id.clone());

            if window_id.is_some() {
                upsert_claude_session(
                    &mut store,
                    session_id,
                    hook_input.transcript_path,
                    hook_input.cwd,
                    niri_id,
                    tmux_id,
                    "waiting",
                );
                save_sessions(&store);
            }
        }

        "SessionEnd" => {
            remove_claude_session(&mut store, &session_id);
            save_sessions(&store);
        }

        "Stop" => {
            if let Some(index) = find_session_index(&store, "claude", &session_id) {
                let is_question = store.sessions[index]
                    .transcript_path
                    .as_ref()
                    .map(|p| ends_with_question(p))
                    .unwrap_or(false);
                store.sessions[index].state = if is_question {
                    "waiting".to_string()
                } else {
                    "idle".to_string()
                };
                store.sessions[index].state_updated = now();
                save_sessions(&store);
            }
        }

        "Notification" => {
            if hook_input.notification_type.as_deref() == Some("permission_prompt") {
                update_claude_state(&mut store, &session_id, "waiting");
                save_sessions(&store);
            }
        }

        "UserPromptSubmit" => {
            let niri_id = get_niri_window_id(&store);
            let tmux_id = get_tmux_window_id();
            let focused_id = niri_id.clone().or_else(|| tmux_id.clone());

            if focused_id.is_some() {
                upsert_claude_session(
                    &mut store,
                    session_id,
                    hook_input.transcript_path,
                    hook_input.cwd,
                    niri_id,
                    tmux_id,
                    "responding",
                );
                save_sessions(&store);
            } else {
                update_claude_state(&mut store, &session_id, "responding");
                save_sessions(&store);
            }
        }

        "PreToolUse" => {
            if let Some(index) = find_session_index(&store, "claude", &session_id) {
                if store.sessions[index].state == "waiting" {
                    store.sessions[index].state = "responding".to_string();
                    store.sessions[index].state_updated = now();
                    save_sessions(&store);
                }
            }
        }

        _ => {}
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct LegacySession {
    session_id: String,
    transcript_path: Option<String>,
    cwd: Option<String>,
    niri_window_id: Option<String>,
    tmux_window_id: Option<String>,
    state: String,
    state_updated: f64,
}

impl LegacySession {
    fn into_session(self, window_id: String) -> SessionEntry {
        let mut niri_window_id = self.niri_window_id;
        let mut tmux_window_id = self.tmux_window_id;

        if niri_window_id.is_none() && tmux_window_id.is_none() {
            if window_id.starts_with('@') {
                tmux_window_id = Some(window_id);
            } else {
                niri_window_id = Some(window_id);
            }
        }

        SessionEntry {
            session_id: self.session_id,
            source: "claude".to_string(),
            transcript_path: self.transcript_path,
            cwd: self.cwd,
            niri_window_id,
            tmux_window_id,
            state: self.state,
            state_updated: self.state_updated,
        }
    }
}
