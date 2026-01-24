use crate::state;
use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box as GtkBox, Label, Orientation, glib};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use niri_ipc::{
    Action, Event, Request, Response, Window, Workspace, WorkspaceReferenceArg, socket::Socket,
};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

const APP_ID: &str = "com.thrawny.agent-switch";
const KEYS: [char; 8] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p'];
const CODEX_ACTIVE_WINDOW_SECS: f64 = 30.0;

#[derive(Debug, Clone, Copy, PartialEq)]
enum AgentState {
    Waiting,
    Responding,
    Idle,
    Unknown,
}

impl AgentState {
    fn from_str(s: &str) -> Self {
        match s {
            "waiting" => Self::Waiting,
            "responding" => Self::Responding,
            "idle" => Self::Idle,
            _ => Self::Unknown,
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Responding => "working",
            Self::Idle => "idle",
            Self::Unknown => "?",
        }
    }

    fn color(&self) -> &'static str {
        match self {
            Self::Waiting => "#f92672",
            Self::Responding => "#a6e22e",
            Self::Idle => "#888888",
            Self::Unknown => "#888888",
        }
    }
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
struct AgentSession {
    agent: String,
    state: AgentState,
    cwd: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CodexRecord {
    timestamp: Option<String>,
    #[serde(rename = "type")]
    record_type: String,
    payload: serde_json::Value,
}

#[derive(Debug, Clone)]
struct CodexSession {
    session_id: String,
    cwd: String,
    state: AgentState,
    state_updated: f64,
}

#[derive(Debug, Clone)]
struct LastMessage {
    role: String,
    text: String,
    timestamp: f64,
}

#[derive(Debug)]
enum Message {
    Toggle,
    Track(TrackEvent),
    ReloadConfig,
    SessionsChanged,
    CodexChanged,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct TrackEvent {
    event: String,
    #[serde(default)]
    agent: Option<String>,
    session_id: String,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    transcript_path: Option<String>,
    #[serde(default)]
    notification_type: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct Project {
    #[allow(dead_code)]
    key: String,
    name: String,
    dir: String,
    #[serde(default)]
    static_workspace: bool,
}

#[derive(Debug, Deserialize, Default)]
struct Config {
    #[serde(default)]
    project: Vec<Project>,
    #[serde(default)]
    ignore: Vec<String>,
    #[serde(default)]
    ignore_unnamed: bool,
}

#[derive(Debug, Clone)]
struct WorkspaceColumn {
    workspace_name: String,
    workspace_ref: WorkspaceReferenceArg,
    workspace_key: char,
    column_index: u32,
    column_key: char,
    app_label: String,
    window_title: Option<String>,
    dir: Option<String>,
    static_workspace: bool,
    window_id: Option<u64>,
}

struct AppState {
    config: Config,
    entries: Vec<WorkspaceColumn>,
    pending_key: Option<char>,
    agent_sessions: HashMap<u64, AgentSession>,
    codex_sessions: HashMap<String, CodexSession>,
}

fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("projects.toml")
}

fn socket_path() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("agent-switch.sock")
}

fn load_config() -> Config {
    if let Ok(content) = std::fs::read_to_string(config_path()) {
        if let Ok(config) = toml::from_str::<Config>(&content) {
            return config;
        }
    }
    Config::default()
}

fn load_agent_sessions() -> HashMap<u64, AgentSession> {
    let store = state::load();
    let mut sessions = HashMap::new();

    for (_, session) in store.sessions.iter() {
        let window_id = match session.window.niri_id.as_ref() {
            Some(id) => id.parse::<u64>().ok(),
            None => continue,
        };
        let Some(window_id) = window_id else { continue };

        sessions.insert(
            window_id,
            AgentSession {
                agent: session.agent.clone(),
                state: AgentState::from_str(&session.state),
                cwd: session.cwd.clone(),
            },
        );
    }
    sessions
}

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

fn load_codex_sessions() -> HashMap<String, CodexSession> {
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

fn path_depth(path: &str) -> usize {
    Path::new(path)
        .components()
        .filter(|c| !matches!(c, std::path::Component::RootDir))
        .count()
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
    let entry_path = Path::new(entry_dir);
    let cwd_path = Path::new(cwd);
    entry_path.starts_with(cwd_path) || cwd_path.starts_with(entry_path)
}

fn match_codex_by_dir<'a>(
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

fn codex_state_for_entry(
    entry: &WorkspaceColumn,
    codex_by_cwd: &HashMap<String, CodexSession>,
) -> Option<AgentState> {
    let title = entry.window_title.as_deref()?.trim();
    if !title.eq_ignore_ascii_case("codex") {
        return None;
    }
    let dir = entry.dir.as_deref()?;
    let dir = shellexpand::tilde(dir).to_string();
    match_codex_by_dir(&dir, codex_by_cwd).map(|entry| entry.state)
}

fn niri_request(request: Request) -> Option<Response> {
    let mut socket = Socket::connect().ok()?;
    match socket.send(request) {
        Ok(Ok(response)) => Some(response),
        _ => None,
    }
}

fn niri_action(action: Action) {
    let _ = niri_request(Request::Action(action));
}

fn niri_workspaces() -> Vec<Workspace> {
    match niri_request(Request::Workspaces) {
        Some(Response::Workspaces(workspaces)) => workspaces,
        _ => Vec::new(),
    }
}

fn niri_windows() -> Vec<Window> {
    match niri_request(Request::Windows) {
        Some(Response::Windows(windows)) => windows,
        _ => Vec::new(),
    }
}

fn get_workspace_by_name(name: &str) -> Option<Workspace> {
    niri_workspaces()
        .into_iter()
        .find(|ws| ws.name.as_deref() == Some(name))
}

fn simplify_label(title: &str, app_id: &str) -> String {
    if app_id.contains("ghostty") || app_id.contains("terminal") || app_id.contains("alacritty") {
        let cleaned = title
            .trim_start_matches(|c: char| !c.is_alphanumeric() && c != '~' && c != '/')
            .trim();
        if cleaned.starts_with('~') {
            let last = cleaned.split('/').next_back().unwrap_or(cleaned);
            format!("~/{}", last)
        } else if cleaned.starts_with('/') {
            cleaned
                .split('/')
                .next_back()
                .unwrap_or(cleaned)
                .to_string()
        } else {
            cleaned.to_string()
        }
    } else {
        app_id.split('.').next_back().unwrap_or(app_id).to_string()
    }
}

fn get_workspace_columns(config: &Config) -> Vec<WorkspaceColumn> {
    use std::collections::{BTreeMap, HashSet};

    let workspaces = niri_workspaces();
    let windows = niri_windows();

    let mut entries = Vec::new();
    let mut seen_workspaces: HashSet<String> = HashSet::new();
    let mut key_idx = 0;

    let add_workspace_entries = |entries: &mut Vec<WorkspaceColumn>,
                                 ws_id: u64,
                                 ws_name: &str,
                                 workspace_ref: WorkspaceReferenceArg,
                                 workspace_key: char,
                                 dir: Option<String>,
                                 static_workspace: bool,
                                 windows_arr: &[&Window]| {
        let mut columns: BTreeMap<usize, Vec<&Window>> = BTreeMap::new();

        for window in windows_arr.iter() {
            if window.workspace_id != Some(ws_id) {
                continue;
            }
            let col_idx = window
                .layout
                .pos_in_scrolling_layout
                .map(|pos| pos.0)
                .unwrap_or(1);
            columns.entry(col_idx).or_default().push(*window);
        }

        let has_columns = columns.keys().any(|&idx| idx >= 2);

        if has_columns {
            for (&col_idx, col_windows) in &columns {
                if col_idx < 2 {
                    continue;
                }
                let key_offset = col_idx - 2;
                if key_offset >= KEYS.len() {
                    continue;
                }
                let column_key = KEYS[key_offset];

                let first_window = col_windows.first();
                let title = first_window.and_then(|w| w.title.as_deref()).unwrap_or("?");
                let app_id = first_window
                    .and_then(|w| w.app_id.as_deref())
                    .unwrap_or("?");
                let window_id = first_window.map(|w| w.id);
                let window_title = first_window.and_then(|w| w.title.clone());
                let app_label = simplify_label(title, app_id);

                entries.push(WorkspaceColumn {
                    workspace_name: ws_name.to_string(),
                    workspace_ref: workspace_ref.clone(),
                    workspace_key,
                    column_index: col_idx as u32,
                    column_key,
                    app_label,
                    window_title,
                    dir: dir.clone(),
                    static_workspace,
                    window_id,
                });
            }
        } else {
            entries.push(WorkspaceColumn {
                workspace_name: ws_name.to_string(),
                workspace_ref: workspace_ref.clone(),
                workspace_key,
                column_index: 2,
                column_key: KEYS[0],
                app_label: "(empty)".to_string(),
                window_title: None,
                dir: dir.clone(),
                static_workspace,
                window_id: None,
            });
        }
    };

    let windows_refs: Vec<&Window> = windows.iter().collect();

    for project in &config.project {
        if key_idx >= KEYS.len() {
            break;
        }
        seen_workspaces.insert(project.name.clone());
        let workspace_key = KEYS[key_idx];

        let ws_id = workspaces
            .iter()
            .find(|ws| ws.name.as_deref() == Some(&project.name))
            .map(|ws| ws.id);

        if let Some(ws_id) = ws_id {
            add_workspace_entries(
                &mut entries,
                ws_id,
                &project.name,
                WorkspaceReferenceArg::Name(project.name.clone()),
                workspace_key,
                Some(project.dir.clone()),
                project.static_workspace,
                &windows_refs,
            );
        } else {
            entries.push(WorkspaceColumn {
                workspace_name: project.name.clone(),
                workspace_ref: WorkspaceReferenceArg::Name(project.name.clone()),
                workspace_key,
                column_index: 2,
                column_key: KEYS[0],
                app_label: "(empty)".to_string(),
                window_title: None,
                dir: Some(project.dir.clone()),
                static_workspace: project.static_workspace,
                window_id: None,
            });
        }

        key_idx += 1;
    }

    let mut remaining: Vec<_> = workspaces
        .iter()
        .filter_map(|ws| {
            let ws_id = ws.id;
            let name_opt = ws.name.as_deref();
            let idx = ws.idx;

            if name_opt.is_none() && config.ignore_unnamed {
                return None;
            }

            let display_name: String = match name_opt {
                Some(n) => n.to_string(),
                None => idx.to_string(),
            };

            if seen_workspaces.contains(&display_name) {
                return None;
            }
            if config.ignore.iter().any(|i| i == &display_name) {
                return None;
            }

            let workspace_ref = match name_opt {
                Some(n) => WorkspaceReferenceArg::Name(n.to_string()),
                None => WorkspaceReferenceArg::Index(idx),
            };

            Some((idx, ws_id, display_name, workspace_ref))
        })
        .collect();

    remaining.sort_by_key(|(idx, _, _, _)| *idx);

    for (_, ws_id, display_name, workspace_ref) in remaining {
        if key_idx >= KEYS.len() {
            break;
        }

        let workspace_key = KEYS[key_idx];

        add_workspace_entries(
            &mut entries,
            ws_id,
            &display_name,
            workspace_ref,
            workspace_key,
            None,
            true,
            &windows_refs,
        );

        key_idx += 1;
    }

    entries
}

fn focus_workspace(reference: WorkspaceReferenceArg) {
    niri_action(Action::FocusWorkspace { reference });
}

fn focus_column(index: u32) {
    niri_action(Action::FocusColumn {
        index: index as usize,
    });
}

fn spawn_terminals(dir: &str) {
    let dir = shellexpand::tilde(dir).to_string();
    for _ in 0..3 {
        Command::new("ghostty")
            .arg(format!("--working-directory={}", dir))
            .spawn()
            .ok();
        std::thread::sleep(std::time::Duration::from_millis(300));
    }
}

fn create_workspace(name: &str, dir: Option<&str>) {
    if get_workspace_by_name(name).is_some() {
        focus_workspace(WorkspaceReferenceArg::Name(name.to_string()));
    } else {
        let max_idx = niri_workspaces().iter().map(|ws| ws.idx).max().unwrap_or(0);
        let new_idx = max_idx.saturating_add(1);
        focus_workspace(WorkspaceReferenceArg::Index(new_idx));
        niri_action(Action::SetWorkspaceName {
            name: name.to_string(),
            workspace: None,
        });
    }

    if let Some(d) = dir {
        std::thread::sleep(std::time::Duration::from_millis(100));
        spawn_terminals(d);
    }
}

fn switch_to_entry(entry: &WorkspaceColumn) {
    if entry.static_workspace {
        focus_workspace(entry.workspace_ref.clone());
        if entry.app_label == "(empty)" {
            if let Some(ref dir) = entry.dir {
                spawn_terminals(dir);
            }
        }
    } else {
        if entry.app_label == "(empty)" {
            create_workspace(&entry.workspace_name, entry.dir.as_deref());
        }
        focus_workspace(entry.workspace_ref.clone());
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    focus_column(entry.column_index);
}

fn send_toggle() -> Result<(), Box<dyn std::error::Error>> {
    let path = socket_path();
    let mut stream = UnixStream::connect(&path)?;
    stream.write_all(b"toggle")?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(())
}

fn start_socket_listener(tx: mpsc::Sender<Message>) {
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
                                let _ = tx.send(Message::Toggle);
                                let _ = stream.write_all(b"ok");
                            } else if let Some(json) = cmd.strip_prefix("track ") {
                                match serde_json::from_str::<TrackEvent>(json) {
                                    Ok(event) => {
                                        let _ = tx.send(Message::Track(event));
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

fn start_config_watcher(tx: mpsc::Sender<Message>) {
    let config = config_path();
    let config_dir = config.parent().map(|p| p.to_path_buf());

    thread::spawn(move || {
        let tx_clone = tx.clone();
        let config_filename = config.file_name().map(|s| s.to_os_string());

        let mut watcher = match RecommendedWatcher::new(
            move |res: Result<notify::Event, notify::Error>| {
                if let Ok(event) = res {
                    let dominated_by_config = event
                        .paths
                        .iter()
                        .any(|p| p.file_name() == config_filename.as_deref());
                    if dominated_by_config {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                let _ = tx_clone.send(Message::ReloadConfig);
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
                eprintln!("Failed to create config watcher: {}", e);
                return;
            }
        };

        if let Some(dir) = config_dir {
            if let Err(e) = watcher.watch(&dir, RecursiveMode::NonRecursive) {
                eprintln!("Failed to watch config directory: {}", e);
                return;
            }
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        }
    });
}

fn start_sessions_watcher(tx: mpsc::Sender<Message>) {
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
                                let _ = tx_clone.send(Message::SessionsChanged);
                            }
                            _ => {}
                        }
                    } else if is_codex_file {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                let _ = tx_clone.send(Message::CodexChanged);
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

fn start_focus_tracker(focused_window: Arc<Mutex<Option<u64>>>) {
    thread::spawn(move || {
        loop {
            let mut socket = match Socket::connect() {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to connect to niri: {}", e);
                    thread::sleep(std::time::Duration::from_secs(1));
                    continue;
                }
            };

            match socket.send(Request::EventStream) {
                Ok(Ok(Response::Handled)) => {}
                Ok(Ok(_)) => {}
                result => {
                    eprintln!("Failed to request event stream: {:?}", result);
                    thread::sleep(std::time::Duration::from_secs(1));
                    continue;
                }
            }

            let mut read_event = socket.read_events();
            while let Ok(event) = read_event() {
                match event {
                    Event::WindowsChanged { windows } => {
                        let focused = windows.iter().find(|w| w.is_focused).map(|w| w.id);
                        *focused_window.lock().unwrap() = focused;
                    }
                    Event::WindowOpenedOrChanged { window } => {
                        if window.is_focused {
                            *focused_window.lock().unwrap() = Some(window.id);
                        }
                    }
                    Event::WindowFocusChanged { id } => {
                        *focused_window.lock().unwrap() = id;
                    }
                    Event::WindowClosed { id } => {
                        let mut guard = focused_window.lock().unwrap();
                        if *guard == Some(id) {
                            *guard = None;
                        }
                    }
                    _ => {}
                }
            }
        }
    });
}

fn build_ui(
    app: &Application,
    rx: mpsc::Receiver<Message>,
    focused_window: Arc<Mutex<Option<u64>>>,
) {
    let window = ApplicationWindow::builder()
        .application(app)
        .default_width(500)
        .build();

    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_anchor(Edge::Top, false);
    window.set_anchor(Edge::Bottom, false);
    window.set_anchor(Edge::Left, false);
    window.set_anchor(Edge::Right, false);

    let config = load_config();
    let entries = get_workspace_columns(&config);
    let agent_sessions = load_agent_sessions();
    let codex_sessions = load_codex_sessions();

    let state = Rc::new(RefCell::new(AppState {
        config,
        entries,
        pending_key: None,
        agent_sessions,
        codex_sessions,
    }));

    let outer_box = GtkBox::new(Orientation::Vertical, 0);
    outer_box.add_css_class("outer");

    let main_box = GtkBox::new(Orientation::Vertical, 10);
    main_box.set_margin_top(20);
    main_box.set_margin_bottom(20);
    main_box.set_margin_start(20);
    main_box.set_margin_end(20);

    {
        let state_ref = state.borrow();
        build_entry_list(
            &main_box,
            &state_ref.entries,
            state_ref.pending_key,
            &state_ref.agent_sessions,
            &state_ref.codex_sessions,
        );
    }
    outer_box.append(&main_box);

    let css_provider = gtk4::CssProvider::new();
    css_provider.load_from_data(
        r#"
        window {
            background-color: transparent;
        }
        .outer {
            background-color: rgba(30, 30, 30, 0.95);
            border-radius: 10px;
            border: 2px solid #f92672;
        }
        label {
            color: #ffffff;
            font-size: 14px;
        }
        label.header {
            font-size: 12px;
            color: #888888;
        }
        label.key {
            color: #f0c674;
            font-family: monospace;
            font-weight: bold;
        }
        label.project {
            color: #888888;
        }
        label.selected {
            color: #b5bd68;
        }
        "#,
    );

    gtk4::style_context_add_provider_for_display(
        &gtk4::gdk::Display::default().unwrap(),
        &css_provider,
        gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    window.set_child(Some(&outer_box));

    let key_controller = gtk4::EventControllerKey::new();
    let state_clone = state.clone();
    let window_clone = window.clone();
    let main_box_clone = main_box.clone();

    key_controller.connect_key_pressed(move |_, keyval, _, _| {
        let key_name = keyval.name().map(|s| s.to_lowercase());
        let Some(key) = key_name.as_deref() else {
            return glib::Propagation::Proceed;
        };

        if key == "q" || key == "escape" {
            let mut state = state_clone.borrow_mut();
            if state.pending_key.is_some() {
                state.pending_key = None;
                let entries = state.entries.clone();
                let agent_sessions = state.agent_sessions.clone();
                let codex_sessions = state.codex_sessions.clone();
                drop(state);
                build_entry_list(
                    &main_box_clone,
                    &entries,
                    None,
                    &agent_sessions,
                    &codex_sessions,
                );
            } else {
                drop(state);
                window_clone.set_visible(false);
            }
            return glib::Propagation::Stop;
        }

        if let Some(pos) = KEYS.iter().position(|&k| k.to_string() == key) {
            let key_char = KEYS[pos];
            let mut state = state_clone.borrow_mut();

            if let Some(first_key) = state.pending_key {
                if let Some(entry) = state
                    .entries
                    .iter()
                    .find(|e| e.workspace_key == first_key && e.column_key == key_char)
                {
                    let entry = entry.clone();
                    state.pending_key = None;
                    drop(state);
                    window_clone.set_visible(false);
                    switch_to_entry(&entry);
                } else {
                    state.pending_key = None;
                    let entries = state.entries.clone();
                    let agent_sessions = state.agent_sessions.clone();
                    let codex_sessions = state.codex_sessions.clone();
                    drop(state);
                    build_entry_list(
                        &main_box_clone,
                        &entries,
                        None,
                        &agent_sessions,
                        &codex_sessions,
                    );
                }
            } else {
                if state.entries.iter().any(|e| e.workspace_key == key_char) {
                    state.pending_key = Some(key_char);
                    let entries = state.entries.clone();
                    let agent_sessions = state.agent_sessions.clone();
                    let codex_sessions = state.codex_sessions.clone();
                    drop(state);
                    build_entry_list(
                        &main_box_clone,
                        &entries,
                        Some(key_char),
                        &agent_sessions,
                        &codex_sessions,
                    );
                }
            }
        }

        glib::Propagation::Stop
    });

    window.add_controller(key_controller);
    window.set_visible(false);
    window.present();
    window.set_visible(false);

    let window_for_poll = window.clone();
    let state_for_poll = state.clone();
    let main_box_for_poll = main_box.clone();
    let focused_window_for_poll = focused_window.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
        while let Ok(msg) = rx.try_recv() {
            match msg {
                Message::Toggle => {
                    let is_visible = window_for_poll.is_visible();
                    if is_visible {
                        window_for_poll.set_visible(false);
                        let mut state = state_for_poll.borrow_mut();
                        state.pending_key = None;
                    } else {
                        // Cleanup stale sessions on toggle
                        let mut store = state::load();
                        state::cleanup_stale(&mut store);
                        state::save(&store);

                        let mut state = state_for_poll.borrow_mut();
                        state.entries = get_workspace_columns(&state.config);
                        state.agent_sessions = load_agent_sessions();
                        state.codex_sessions = load_codex_sessions();
                        state.pending_key = None;
                        let entries = state.entries.clone();
                        let agent_sessions = state.agent_sessions.clone();
                        let codex_sessions = state.codex_sessions.clone();
                        drop(state);
                        build_entry_list(
                            &main_box_for_poll,
                            &entries,
                            None,
                            &agent_sessions,
                            &codex_sessions,
                        );
                        window_for_poll.set_visible(true);
                        window_for_poll.present();
                    }
                }
                Message::ReloadConfig => {
                    let mut state = state_for_poll.borrow_mut();
                    state.config = load_config();
                    state.entries = get_workspace_columns(&state.config);
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let agent_sessions = state.agent_sessions.clone();
                        let codex_sessions = state.codex_sessions.clone();
                        drop(state);
                        build_entry_list(
                            &main_box_for_poll,
                            &entries,
                            pending,
                            &agent_sessions,
                            &codex_sessions,
                        );
                    }
                }
                Message::SessionsChanged => {
                    let mut state = state_for_poll.borrow_mut();
                    state.agent_sessions = load_agent_sessions();
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let agent_sessions = state.agent_sessions.clone();
                        let codex_sessions = state.codex_sessions.clone();
                        drop(state);
                        build_entry_list(
                            &main_box_for_poll,
                            &entries,
                            pending,
                            &agent_sessions,
                            &codex_sessions,
                        );
                    }
                }
                Message::CodexChanged => {
                    let mut state = state_for_poll.borrow_mut();
                    state.codex_sessions = load_codex_sessions();
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let agent_sessions = state.agent_sessions.clone();
                        let codex_sessions = state.codex_sessions.clone();
                        drop(state);
                        build_entry_list(
                            &main_box_for_poll,
                            &entries,
                            pending,
                            &agent_sessions,
                            &codex_sessions,
                        );
                    }
                }
                Message::Track(event) => {
                    let focused_id = *focused_window_for_poll.lock().unwrap();
                    handle_track_event(&event, focused_id);
                }
            }
        }
        glib::ControlFlow::Continue
    });
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
    use std::process::Command as StdCommand;

    let output = match StdCommand::new("tail")
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

fn build_entry_list(
    container: &GtkBox,
    entries: &[WorkspaceColumn],
    pending_key: Option<char>,
    agent_sessions: &HashMap<u64, AgentSession>,
    codex_sessions: &HashMap<String, CodexSession>,
) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }

    let header_text = if let Some(key) = pending_key {
        format!("Select column for [{}] (q/Esc to cancel)", key)
    } else {
        "Select workspace+column (q/Esc to cancel)".to_string()
    };
    let header = Label::new(Some(&header_text));
    header.add_css_class("header");
    container.append(&header);

    let filtered: Vec<_> = if let Some(key) = pending_key {
        entries.iter().filter(|e| e.workspace_key == key).collect()
    } else {
        entries.iter().collect()
    };

    for entry in filtered {
        let row = GtkBox::new(Orientation::Horizontal, 10);

        let key_text = format!("[{}{}]", entry.workspace_key, entry.column_key);
        let key_label = Label::new(Some(&key_text));
        key_label.add_css_class("key");
        row.append(&key_label);

        let name_text = if let Some(window_id) = entry.window_id {
            if let Some(session) = agent_sessions.get(&window_id) {
                format!(
                    "{} / {} <span color=\"{}\" weight=\"bold\">[{}]</span>",
                    entry.workspace_name,
                    session.agent,
                    session.state.color(),
                    session.state.label()
                )
            } else if let Some(state) = codex_state_for_entry(entry, codex_sessions) {
                format!(
                    "{} / codex <span color=\"{}\" weight=\"bold\">[{}]</span>",
                    entry.workspace_name,
                    state.color(),
                    state.label()
                )
            } else {
                format!("{} / {}", entry.workspace_name, entry.app_label)
            }
        } else {
            format!("{} / {}", entry.workspace_name, entry.app_label)
        };

        let name_label = Label::new(None);
        name_label.set_markup(&name_text);
        name_label.add_css_class("project");
        row.append(&name_label);

        container.append(&row);
    }
}

pub fn run(toggle: bool) -> glib::ExitCode {
    if toggle {
        if let Err(e) = send_toggle() {
            eprintln!("Failed to toggle: {} (is daemon running?)", e);
            std::process::exit(1);
        }
        std::process::exit(0);
    }

    let (tx, rx) = mpsc::channel();
    let focused_window: Arc<Mutex<Option<u64>>> = Arc::new(Mutex::new(None));

    start_socket_listener(tx.clone());
    start_config_watcher(tx.clone());
    start_sessions_watcher(tx);
    start_focus_tracker(focused_window.clone());

    let rx = Rc::new(RefCell::new(Some(rx)));
    let focused_window = Rc::new(RefCell::new(Some(focused_window)));

    let app = Application::builder()
        .application_id(APP_ID)
        .flags(gtk4::gio::ApplicationFlags::NON_UNIQUE)
        .build();

    let rx_clone = rx.clone();
    let focused_clone = focused_window.clone();
    app.connect_activate(move |app| {
        if let (Some(rx), Some(focused)) = (
            rx_clone.borrow_mut().take(),
            focused_clone.borrow_mut().take(),
        ) {
            build_ui(app, rx, focused);
        }
    });

    app.run_with_args::<&str>(&[])
}
