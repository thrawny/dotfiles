use crate::state::{self, SessionStore};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

const CODEX_ACTIVE_WINDOW_SECS: f64 = 30.0;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    Waiting,
    Responding,
    Idle,
    #[serde(other)]
    Unknown,
}

impl AgentState {
    pub fn from_str(s: &str) -> Self {
        match s {
            "waiting" => Self::Waiting,
            "responding" => Self::Responding,
            "idle" => Self::Idle,
            _ => Self::Unknown,
        }
    }

    /// Get display label for the state (used by niri GTK overlay)
    #[cfg_attr(not(feature = "niri"), allow(dead_code))]
    pub fn label(&self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Responding => "working",
            Self::Idle => "idle",
            Self::Unknown => "?",
        }
    }

    /// Get display color for the state (used by niri GTK overlay)
    #[cfg_attr(not(feature = "niri"), allow(dead_code))]
    pub fn color(&self) -> &'static str {
        match self {
            Self::Waiting => "#f92672",
            Self::Responding => "#a6e22e",
            Self::Idle => "#888888",
            Self::Unknown => "#888888",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct AgentSession {
    pub agent: String,
    pub state: AgentState,
    pub cwd: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CodexRecord {
    timestamp: Option<String>,
    #[serde(rename = "type")]
    record_type: String,
    payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct CodexSession {
    pub session_id: String,
    pub cwd: String,
    pub state: AgentState,
    pub state_updated: f64,
}

#[derive(Debug, Clone)]
struct LastMessage {
    role: String,
    text: String,
    timestamp: f64,
}

#[derive(Debug)]
pub enum DaemonMessage {
    Toggle,
    Track(TrackEvent),
    List(std::sync::mpsc::Sender<ListResponse>),
    SessionsChanged,
    CodexChanged,
    Shutdown,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TrackEvent {
    pub event: String,
    #[serde(default)]
    pub agent: Option<String>,
    pub session_id: String,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub transcript_path: Option<String>,
    #[serde(default)]
    pub notification_type: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ListResponse {
    pub claude: Vec<ClaudeListEntry>,
    pub codex: Vec<CodexListEntry>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClaudeListEntry {
    pub session_id: String,
    pub agent: String,
    pub cwd: Option<String>,
    pub state: AgentState,
    pub state_updated: f64,
    pub window_id: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub tmux_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub niri_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CodexListEntry {
    pub session_id: String,
    pub cwd: String,
    pub state: AgentState,
    pub state_updated: f64,
}

#[derive(Debug, Default)]
pub struct SessionCache {
    pub agent_sessions: HashMap<String, AgentSession>,
    pub codex_sessions: HashMap<String, CodexSession>,
    pub store: SessionStore,
}

impl SessionCache {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reload_agent_sessions(&mut self) {
        self.store = state::load();
        self.agent_sessions.clear();

        for (key, session) in self.store.sessions.iter() {
            self.agent_sessions.insert(
                key.clone(),
                AgentSession {
                    agent: session.agent.clone(),
                    state: AgentState::from_str(&session.state),
                    cwd: session.cwd.clone(),
                },
            );
        }
    }

    pub fn reload_codex_sessions(&mut self) {
        self.codex_sessions = load_codex_sessions();
    }

    pub fn build_list_response(&self) -> ListResponse {
        let claude: Vec<ClaudeListEntry> = self
            .store
            .sessions
            .iter()
            .map(|(key, session)| ClaudeListEntry {
                session_id: session.session_id.clone(),
                agent: session.agent.clone(),
                cwd: session.cwd.clone(),
                state: AgentState::from_str(&session.state),
                state_updated: session.state_updated,
                window_id: key.clone(),
                tmux_id: session.window.tmux_id.clone(),
                niri_id: session.window.niri_id.clone(),
            })
            .collect();

        let codex: Vec<CodexListEntry> = self
            .codex_sessions
            .values()
            .map(|session| CodexListEntry {
                session_id: session.session_id.clone(),
                cwd: session.cwd.clone(),
                state: session.state,
                state_updated: session.state_updated,
            })
            .collect();

        ListResponse { claude, codex }
    }
}

pub fn socket_path() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("agent-switch.sock")
}

pub fn start_socket_listener(tx: mpsc::Sender<DaemonMessage>, cache: Arc<Mutex<SessionCache>>) {
    let path = socket_path();
    let _ = std::fs::remove_file(&path);

    let listener = match UnixListener::bind(&path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind socket: {}", e);
            return;
        }
    };

    thread::spawn(move || {
        for stream in listener.incoming() {
            match stream {
                Ok(mut stream) => {
                    let mut buf = [0u8; 4096];
                    if let Ok(count) = stream.read(&mut buf) {
                        if count > 0 {
                            let cmd = String::from_utf8_lossy(&buf[..count]);
                            let cmd = cmd.trim();
                            if cmd == "toggle" {
                                let _ = tx.send(DaemonMessage::Toggle);
                                let _ = stream.write_all(b"ok");
                            } else if cmd == "list" {
                                let (resp_tx, resp_rx) = mpsc::channel();
                                if tx.send(DaemonMessage::List(resp_tx)).is_ok() {
                                    if let Ok(response) = resp_rx.recv() {
                                        if let Ok(json) = serde_json::to_string(&response) {
                                            let _ = stream.write_all(json.as_bytes());
                                        } else {
                                            let _ =
                                                stream.write_all(b"error: serialization failed");
                                        }
                                    } else {
                                        // Daemon busy or shutting down, read cache directly
                                        let cache = cache.lock().unwrap();
                                        let response = cache.build_list_response();
                                        if let Ok(json) = serde_json::to_string(&response) {
                                            let _ = stream.write_all(json.as_bytes());
                                        } else {
                                            let _ =
                                                stream.write_all(b"error: serialization failed");
                                        }
                                    }
                                } else {
                                    let _ = stream.write_all(b"error: daemon not responding");
                                }
                            } else if let Some(json) = cmd.strip_prefix("track ") {
                                match serde_json::from_str::<TrackEvent>(json) {
                                    Ok(event) => {
                                        let _ = tx.send(DaemonMessage::Track(event));
                                        let _ = stream.write_all(b"ok");
                                    }
                                    Err(e) => {
                                        let _ =
                                            stream.write_all(format!("error: {}", e).as_bytes());
                                    }
                                }
                            } else {
                                let _ = stream.write_all(b"unknown command");
                            }
                        }
                    }
                }
                Err(e) => {
                    eprintln!("Socket error: {}", e);
                }
            }
        }
    });
}

pub fn start_sessions_watcher(tx: mpsc::Sender<DaemonMessage>) {
    let state_file = state::state_file();
    let state_dir = state_file.parent().map(|p| p.to_path_buf());
    let codex_dir = codex_sessions_root();

    thread::spawn(move || {
        let tx_clone = tx.clone();
        let state_filename = state_file.file_name().map(|s| s.to_os_string());

        let mut watcher = match RecommendedWatcher::new(
            move |res: Result<notify::Event, notify::Error>| {
                if let Ok(event) = res {
                    let is_state_file = event
                        .paths
                        .iter()
                        .any(|p| p.file_name() == state_filename.as_deref());
                    let is_codex_file = event.paths.iter().any(|p| is_codex_rollout_file(p));
                    if is_state_file {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                let _ = tx_clone.send(DaemonMessage::SessionsChanged);
                            }
                            _ => {}
                        }
                    } else if is_codex_file {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                let _ = tx_clone.send(DaemonMessage::CodexChanged);
                            }
                            _ => {}
                        }
                    }
                }
            },
            notify::Config::default(),
        ) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("Failed to create sessions watcher: {}", e);
                return;
            }
        };

        if let Some(dir) = state_dir {
            let _ = std::fs::create_dir_all(&dir);
            if let Err(e) = watcher.watch(&dir, RecursiveMode::NonRecursive) {
                eprintln!("Failed to watch state directory: {}", e);
                return;
            }
        }

        if codex_dir.exists() {
            if let Err(e) = watcher.watch(&codex_dir, RecursiveMode::Recursive) {
                eprintln!("Failed to watch codex sessions directory: {}", e);
                return;
            }
        }

        loop {
            std::thread::sleep(std::time::Duration::from_secs(3600));
        }
    });
}

/// Monitor tmux sockets for daemon lifecycle (headless mode only)
pub fn start_tmux_monitor(tx: mpsc::Sender<DaemonMessage>) {
    thread::spawn(move || {
        loop {
            thread::sleep(std::time::Duration::from_secs(5));
            let sockets = find_tmux_sockets();
            if sockets.is_empty() {
                eprintln!("No tmux sockets found, shutting down daemon");
                let _ = tx.send(DaemonMessage::Shutdown);
                return;
            }
        }
    });
}

fn find_tmux_sockets() -> Vec<PathBuf> {
    let uid = unsafe { libc::getuid() };
    let base = if cfg!(target_os = "macos") {
        "/private/tmp"
    } else {
        "/tmp"
    };
    let dir = PathBuf::from(format!("{}/tmux-{}", base, uid));
    fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .collect()
}

// Codex session loading functions

fn codex_sessions_root() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_default()
        .join(".codex")
        .join("sessions")
}

fn is_codex_rollout_file(path: &Path) -> bool {
    let filename = match path.file_name().and_then(|name| name.to_str()) {
        Some(name) => name,
        None => return false,
    };
    filename.starts_with("rollout-") && filename.ends_with(".jsonl")
}

fn walk_codex_files(dir: &Path, files: &mut Vec<PathBuf>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk_codex_files(&path, files);
            } else if is_codex_rollout_file(path.as_path()) {
                files.push(path);
            }
        }
    }
}

fn update_codex_session(
    codex: &mut HashMap<String, CodexSession>,
    session_id: &str,
    cwd: Option<&str>,
    state: &str,
    state_updated: Option<f64>,
) {
    let updated = state_updated.unwrap_or_else(state::now);
    let entry = codex.entry(session_id.to_string()).or_insert(CodexSession {
        session_id: session_id.to_string(),
        cwd: String::new(),
        state: AgentState::from_str(state),
        state_updated: updated,
    });

    if entry.cwd.is_empty() {
        if let Some(value) = cwd {
            entry.cwd = value.to_string();
        }
    }
    entry.state = AgentState::from_str(state);
    entry.state_updated = updated;
}

fn update_last_message(
    last_message: &mut HashMap<String, LastMessage>,
    session_id: &str,
    role: &str,
    text: &str,
    timestamp: f64,
) {
    let replace = match last_message.get(session_id) {
        Some(existing) => timestamp >= existing.timestamp,
        None => true,
    };
    if replace {
        last_message.insert(
            session_id.to_string(),
            LastMessage {
                role: role.to_string(),
                text: text.to_string(),
                timestamp,
            },
        );
    }
}

fn handle_codex_record(
    codex: &mut HashMap<String, CodexSession>,
    last_message: &mut HashMap<String, LastMessage>,
    record: CodexRecord,
    fallback_session_id: Option<&str>,
    fallback_cwd: Option<&str>,
) {
    let record_ts = record_timestamp(&record);
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
            update_codex_session(codex, session_id, cwd, "idle", record_ts);
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
            let Some(ts) = record_ts else {
                return;
            };
            match event_type {
                "user_message" => {
                    update_codex_session(codex, session_id, fallback_cwd, "responding", record_ts);
                    update_last_message(last_message, session_id, "user", "", ts);
                }
                "agent_message" => {
                    update_codex_session(codex, session_id, fallback_cwd, "idle", record_ts);
                    update_last_message(last_message, session_id, "assistant", "", ts);
                }
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
                update_codex_session(codex, session_id, fallback_cwd, "responding", record_ts);
                let Some(ts) = record_ts else {
                    return;
                };
                let text = extract_assistant_text(&record.payload).unwrap_or_default();
                update_last_message(last_message, session_id, "assistant", &text, ts);
            }
        }
        _ => {}
    }
}

fn process_codex_file(
    path: &Path,
    codex: &mut HashMap<String, CodexSession>,
    last_message: &mut HashMap<String, LastMessage>,
) {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(_) => return,
    };
    let reader = BufReader::new(file);
    let mut session_id: Option<String> = None;
    let mut cwd: Option<String> = None;

    for line in reader.lines().map_while(Result::ok) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let record = match serde_json::from_str::<CodexRecord>(trimmed) {
            Ok(record) => record,
            Err(_) => continue,
        };
        if session_id.is_none() || cwd.is_none() {
            if let Some((id, dir)) = read_codex_file_meta(path) {
                session_id = Some(id);
                cwd = Some(dir);
            }
        }
        handle_codex_record(
            codex,
            last_message,
            record,
            session_id.as_deref(),
            cwd.as_deref(),
        );
    }
}

fn read_codex_file_meta(path: &Path) -> Option<(String, String)> {
    let file = fs::File::open(path).ok()?;
    let reader = BufReader::new(file);
    for line in reader.lines().map_while(Result::ok) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let record = serde_json::from_str::<CodexRecord>(trimmed).ok()?;
        if record.record_type != "session_meta" {
            continue;
        }
        let session_id = record
            .payload
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let cwd = record
            .payload
            .get("cwd")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if session_id.is_empty() || cwd.is_empty() {
            return None;
        }
        return Some((session_id, cwd));
    }
    None
}

pub fn load_codex_sessions() -> HashMap<String, CodexSession> {
    let mut codex: HashMap<String, CodexSession> = HashMap::new();
    let mut last_message: HashMap<String, LastMessage> = HashMap::new();
    let mut mtime_by_cwd: HashMap<String, f64> = HashMap::new();
    let root = codex_sessions_root();
    if root.exists() {
        let mut files = Vec::new();
        walk_codex_files(root.as_path(), &mut files);

        let mut by_cwd: HashMap<String, (std::time::SystemTime, PathBuf)> = HashMap::new();
        for file in files {
            let meta = match fs::metadata(&file).and_then(|m| m.modified()) {
                Ok(modified) => modified,
                Err(_) => continue,
            };
            let (_, cwd) = match read_codex_file_meta(file.as_path()) {
                Some(info) => info,
                None => continue,
            };
            let replace = match by_cwd.get(&cwd) {
                Some((existing, _)) => meta > *existing,
                None => true,
            };
            if replace {
                by_cwd.insert(cwd, (meta, file));
            }
        }

        for (cwd, (meta, file)) in by_cwd.iter() {
            let mtime = meta
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs_f64())
                .unwrap_or(0.0);
            mtime_by_cwd.insert(cwd.clone(), mtime);
            process_codex_file(file.as_path(), &mut codex, &mut last_message);
        }
    }

    apply_codex_recent_activity(&mut codex, &mtime_by_cwd);
    apply_codex_idle_timeout(&mut codex);
    apply_codex_waiting(&mut codex, &last_message);

    let mut by_cwd: HashMap<String, CodexSession> = HashMap::new();
    for entry in codex.values() {
        if entry.cwd.is_empty() {
            continue;
        }
        let replace = match by_cwd.get(&entry.cwd) {
            Some(existing) => entry.state_updated >= existing.state_updated,
            None => true,
        };
        if replace {
            by_cwd.insert(entry.cwd.clone(), entry.clone());
        }
    }
    by_cwd
}

fn apply_codex_recent_activity(
    codex: &mut HashMap<String, CodexSession>,
    mtime_by_cwd: &HashMap<String, f64>,
) {
    let now = state::now();
    for entry in codex.values_mut() {
        let Some(mtime) = mtime_by_cwd.get(&entry.cwd) else {
            continue;
        };
        if *mtime > entry.state_updated {
            entry.state_updated = *mtime;
        }
        if now - *mtime <= CODEX_ACTIVE_WINDOW_SECS && entry.state != AgentState::Waiting {
            entry.state = AgentState::Responding;
        }
    }
}

fn record_timestamp(record: &CodexRecord) -> Option<f64> {
    record
        .timestamp
        .as_deref()
        .and_then(parse_rfc3339_epoch)
        .or_else(|| {
            record
                .payload
                .get("timestamp")
                .and_then(|v| v.as_str())
                .and_then(parse_rfc3339_epoch)
        })
}

fn parse_rfc3339_epoch(value: &str) -> Option<f64> {
    OffsetDateTime::parse(value, &Rfc3339)
        .ok()
        .map(|dt| dt.unix_timestamp_nanos() as f64 / 1_000_000_000.0)
}

fn apply_codex_idle_timeout(codex: &mut HashMap<String, CodexSession>) {
    let now = state::now();
    for entry in codex.values_mut() {
        if entry.state == AgentState::Responding && now - entry.state_updated > 10.0 {
            entry.state = AgentState::Idle;
        }
    }
}

fn apply_codex_waiting(
    codex: &mut HashMap<String, CodexSession>,
    last_message: &HashMap<String, LastMessage>,
) {
    for entry in codex.values_mut() {
        if entry.state != AgentState::Idle {
            continue;
        }
        if let Some(message) = last_message.get(&entry.session_id)
            && message.role == "assistant"
            && message.text.trim_end().ends_with('?')
        {
            entry.state = AgentState::Waiting;
        }
    }
}

fn extract_assistant_text(payload: &serde_json::Value) -> Option<String> {
    let content = payload.get("content")?.as_array()?;
    let mut last_text: Option<String> = None;
    for item in content {
        let item_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if (item_type == "text" || item_type == "output_text" || item_type == "input_text")
            && let Some(text) = item.get("text").and_then(|v| v.as_str())
        {
            last_text = Some(text.to_string());
        }
    }
    last_text
}

/// Codex directory matching helpers (for tmux picker)
pub fn match_codex_by_dir<'a>(
    entry_dir: &str,
    entries: &'a HashMap<String, CodexSession>,
) -> Option<&'a CodexSession> {
    let mut best: Option<(&CodexSession, usize)> = None;
    for (cwd, entry) in entries.iter() {
        if !should_match_dir(entry_dir, cwd) {
            continue;
        }
        let depth = path_depth(cwd);
        if best
            .as_ref()
            .map(|(current, current_depth)| {
                depth > *current_depth
                    || (depth == *current_depth && entry.state_updated > current.state_updated)
            })
            .unwrap_or(true)
        {
            best = Some((entry, depth));
        }
    }
    best.map(|(entry, _)| entry)
}

fn should_match_dir(entry_dir: &str, cwd: &str) -> bool {
    if cwd.is_empty() || cwd == "/" {
        return false;
    }
    if let Some(home) = dirs::home_dir()
        && cwd == home.to_string_lossy()
    {
        return false;
    }
    // Match if entry_dir is equal to or a subdirectory of cwd
    let entry_path = Path::new(entry_dir);
    let cwd_path = Path::new(cwd);
    entry_path.starts_with(cwd_path)
}

fn path_depth(path: &str) -> usize {
    Path::new(path)
        .components()
        .filter(|c| !matches!(c, std::path::Component::RootDir))
        .count()
}

/// Run the headless daemon
pub fn run_headless() {
    let (tx, rx) = mpsc::channel();
    let cache = Arc::new(Mutex::new(SessionCache::new()));

    // Initial load
    {
        let mut cache = cache.lock().unwrap();
        cache.reload_agent_sessions();
        cache.reload_codex_sessions();
    }

    eprintln!("Starting headless daemon, listening on {:?}", socket_path());

    start_socket_listener(tx.clone(), cache.clone());
    start_sessions_watcher(tx.clone());
    start_tmux_monitor(tx.clone());

    loop {
        let msg = match rx.recv() {
            Ok(msg) => msg,
            Err(_) => break,
        };

        match msg {
            DaemonMessage::Toggle => {
                // No-op in headless mode
            }
            DaemonMessage::Track(event) => {
                handle_track_event(&event, None);
                let mut cache = cache.lock().unwrap();
                cache.reload_agent_sessions();
            }
            DaemonMessage::List(resp_tx) => {
                let cache = cache.lock().unwrap();
                let response = cache.build_list_response();
                let _ = resp_tx.send(response);
            }
            DaemonMessage::SessionsChanged => {
                let mut cache = cache.lock().unwrap();
                cache.reload_agent_sessions();
            }
            DaemonMessage::CodexChanged => {
                let mut cache = cache.lock().unwrap();
                cache.reload_codex_sessions();
            }
            DaemonMessage::Shutdown => {
                eprintln!("Daemon shutting down");
                break;
            }
        }
    }
}

fn handle_track_event(event: &TrackEvent, focused_window_id: Option<u64>) {
    let agent = event.agent.as_deref().unwrap_or("claude");
    let session_id = &event.session_id;
    let mut store = state::load();

    match event.event.as_str() {
        "session-start" => {
            let Some(window_id) = focused_window_id else {
                return;
            };
            let session = state::Session {
                agent: agent.to_string(),
                session_id: session_id.to_string(),
                cwd: event.cwd.clone(),
                state: "waiting".to_string(),
                state_updated: state::now(),
                window: state::WindowId {
                    niri_id: Some(window_id.to_string()),
                    tmux_id: None,
                },
            };
            store.sessions.insert(window_id.to_string(), session);
        }
        "session-end" => {
            let key = store
                .sessions
                .iter()
                .find(|(_, s)| s.agent == agent && s.session_id == *session_id)
                .map(|(k, _)| k.clone());
            if let Some(key) = key {
                store.sessions.remove(&key);
            }
        }
        "prompt-submit" => {
            if let Some(session) = state::find_by_session_id_mut(&mut store, agent, session_id) {
                session.state = "responding".to_string();
                session.state_updated = state::now();
            } else if let Some(window_id) = focused_window_id {
                let session = state::Session {
                    agent: agent.to_string(),
                    session_id: session_id.to_string(),
                    cwd: event.cwd.clone(),
                    state: "responding".to_string(),
                    state_updated: state::now(),
                    window: state::WindowId {
                        niri_id: Some(window_id.to_string()),
                        tmux_id: None,
                    },
                };
                store.sessions.insert(window_id.to_string(), session);
            }
        }
        "stop" => {
            if let Some(session) = state::find_by_session_id_mut(&mut store, agent, session_id) {
                let is_question = event
                    .transcript_path
                    .as_ref()
                    .map(|p| ends_with_question(p))
                    .unwrap_or(false);
                session.state = if is_question { "waiting" } else { "idle" }.to_string();
                session.state_updated = state::now();
            }
        }
        "notification" => {
            if event.notification_type.as_deref() == Some("permission_prompt") {
                if let Some(session) = state::find_by_session_id_mut(&mut store, agent, session_id)
                {
                    session.state = "waiting".to_string();
                    session.state_updated = state::now();
                }
            }
        }
        _ => {}
    }

    state::save(&store);
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
                    if item.get("type").and_then(|t| t.as_str()) == Some("text") {
                        if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                            last_text = Some(text.to_string());
                        }
                    }
                }
            }
        }
    }

    last_text
        .map(|t| t.trim_end().ends_with('?'))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_should_match_dir_exact_match() {
        assert!(should_match_dir(
            "/Users/jonas/code/project",
            "/Users/jonas/code/project"
        ));
    }

    #[test]
    fn test_should_match_dir_rejects_parent() {
        // Entry in parent dir should NOT match codex session in child
        assert!(!should_match_dir(
            "/Users/jonas/code",
            "/Users/jonas/code/project"
        ));
    }

    #[test]
    fn test_should_match_dir_allows_subdirectory() {
        // Entry in subdirectory SHOULD match codex session in parent
        assert!(should_match_dir(
            "/Users/jonas/code/project/src",
            "/Users/jonas/code/project"
        ));
    }

    #[test]
    fn test_should_match_dir_rejects_empty() {
        assert!(!should_match_dir("/Users/jonas/code", ""));
    }

    #[test]
    fn test_should_match_dir_rejects_root() {
        assert!(!should_match_dir("/Users/jonas/code", "/"));
    }

    #[test]
    fn test_should_match_dir_rejects_sibling() {
        assert!(!should_match_dir(
            "/Users/jonas/code/other",
            "/Users/jonas/code/project"
        ));
    }
}
