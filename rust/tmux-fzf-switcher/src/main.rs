use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::fs::OpenOptions;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};

const KEYS: [char; 12] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p', 'n', 'm', ',', '.'];

#[derive(Debug, Serialize, Deserialize)]
#[allow(dead_code)]
struct SessionStore {
    version: u32,
    sessions: Vec<SessionEntry>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[allow(dead_code)]
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

#[derive(Debug, Deserialize)]
struct CodexRecord {
    timestamp: Option<String>,
    #[serde(rename = "type")]
    record_type: String,
    payload: serde_json::Value,
}

#[derive(Debug, Clone)]
struct WindowRow {
    session_name: String,
    session_index: String,
    window_id: String,
    window_name: String,
    pane_path: String,
    pane_command: String,
}

struct RawModeGuard;

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        let _ = stty_command(&["sane"]);
    }
}

fn enable_raw_mode() -> Option<RawModeGuard> {
    let status = stty_command(&["-echo", "-icanon", "min", "1", "time", "0"])?;
    if status.success() {
        Some(RawModeGuard)
    } else {
        None
    }
}

fn stty_command(args: &[&str]) -> Option<std::process::ExitStatus> {
    let mut cmd = Command::new("stty");
    if cfg!(target_os = "macos") {
        cmd.args(["-f", "/dev/tty"]);
    } else {
        cmd.args(["-F", "/dev/tty"]);
    }
    cmd.args(args).status().ok()
}

struct Tty {
    file: std::fs::File,
}

impl Tty {
    fn open() -> Option<Self> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/tty")
            .ok()?;
        Some(Self { file })
    }

    fn read_key(&mut self) -> Option<char> {
        let mut buf = [0u8; 1];
        if self.file.read_exact(&mut buf).is_ok() {
            Some(buf[0] as char)
        } else {
            None
        }
    }

    fn write_all(&mut self, text: &str) {
        let _ = self.file.write_all(text.as_bytes());
    }

    fn flush(&mut self) {
        let _ = self.file.flush();
    }
}

fn read_key(stdin_fallback: bool, tty: &mut Option<Tty>) -> Option<char> {
    if let Some(tty) = tty.as_mut() {
        return tty.read_key();
    }
    if !stdin_fallback {
        return None;
    }
    let mut buf = [0u8; 1];
    if io::stdin().read_exact(&mut buf).is_ok() {
        Some(buf[0] as char)
    } else {
        None
    }
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

fn load_sessions() -> Vec<SessionEntry> {
    debug_log(&format!(
        "sessions file: {}",
        sessions_file().to_string_lossy()
    ));
    let path = sessions_file();
    if let Ok(content) = fs::read_to_string(&path)
        && let Ok(store) = serde_json::from_str::<SessionStore>(&content)
    {
        return store.sessions;
    }
    Vec::new()
}

fn session_order_path() -> PathBuf {
    if let Ok(config_home) = env::var("XDG_CONFIG_HOME") {
        return PathBuf::from(config_home)
            .join("tmux")
            .join("session-order.conf");
    }
    dirs::home_dir()
        .unwrap_or_default()
        .join(".config")
        .join("tmux")
        .join("session-order.conf")
}

fn load_session_order() -> Vec<String> {
    let path = session_order_path();
    debug_log(&format!("session order file: {}", path.to_string_lossy()));
    let content = match fs::read_to_string(&path) {
        Ok(content) => content,
        Err(_) => return Vec::new(),
    };

    let mut in_block = false;
    let mut items = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if !in_block {
            if trimmed.starts_with("SESSION_ORDER") && trimmed.contains('(') {
                in_block = true;
            } else {
                continue;
            }
        } else if trimmed == ")" {
            break;
        }

        if !in_block {
            continue;
        }

        let cleaned = trimmed
            .trim_end_matches(')')
            .trim_matches('(')
            .trim()
            .strip_prefix("SESSION_ORDER=")
            .unwrap_or(trimmed)
            .trim();
        if cleaned.is_empty() || cleaned.starts_with('#') {
            continue;
        }
        for token in cleaned.split_whitespace() {
            let value = token.trim_matches('"').trim_matches('\'');
            if !value.is_empty() && value != "\\" && value != "SESSION_ORDER=" {
                items.push(value.to_string());
            }
        }
    }

    if !items.is_empty() {
        return items;
    }

    Vec::new()
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
    codex: &mut HashMap<String, SessionEntry>,
    session_id: &str,
    cwd: Option<&str>,
    state: &str,
    state_updated: Option<f64>,
) {
    let updated = state_updated.unwrap_or_else(now_epoch);
    let entry = codex.entry(session_id.to_string()).or_insert(SessionEntry {
        session_id: session_id.to_string(),
        source: "codex".to_string(),
        transcript_path: None,
        cwd: None,
        niri_window_id: None,
        tmux_window_id: None,
        state: state.to_string(),
        state_updated: updated,
    });

    if entry.cwd.is_none() {
        entry.cwd = cwd.map(|value| value.to_string());
    }
    entry.state = state.to_string();
    entry.state_updated = updated;
}

#[derive(Clone)]
struct LastMessage {
    role: String,
    text: String,
    timestamp: f64,
}

fn handle_codex_record(
    codex: &mut HashMap<String, SessionEntry>,
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

fn process_codex_file(
    path: &Path,
    codex: &mut HashMap<String, SessionEntry>,
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
        if let Ok(record) = serde_json::from_str::<CodexRecord>(trimmed) {
            if record.record_type == "session_meta" {
                if let Some(id) = record.payload.get("id").and_then(|v| v.as_str()) {
                    session_id = Some(id.to_string());
                }
                if let Some(value) = record.payload.get("cwd").and_then(|v| v.as_str()) {
                    cwd = Some(value.to_string());
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

fn load_codex_sessions() -> HashMap<String, SessionEntry> {
    let mut codex = HashMap::new();
    let mut last_message: HashMap<String, LastMessage> = HashMap::new();
    let root = codex_sessions_root();
    if root.exists() {
        let mut files = Vec::new();
        walk_codex_files(root.as_path(), &mut files);
        debug_log(&format!("codex files: {}", files.len()));

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

        debug_log(&format!("codex files (latest per cwd): {}", by_cwd.len()));
        let mut selected: Vec<(std::time::SystemTime, PathBuf)> = by_cwd.into_values().collect();
        selected.sort_by_key(|(meta, _)| *meta);
        for (_, file) in selected {
            process_codex_file(file.as_path(), &mut codex, &mut last_message);
        }
    }
    debug_log(&format!("codex sessions: {}", codex.len()));
    apply_codex_idle_timeout(&mut codex);
    apply_codex_waiting(&mut codex, &last_message);
    codex
}

fn now_epoch() -> f64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
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

fn apply_codex_idle_timeout(codex: &mut HashMap<String, SessionEntry>) {
    let now = now_epoch();
    for entry in codex.values_mut() {
        if entry.state == "responding" && now - entry.state_updated > 10.0 {
            entry.state = "idle".to_string();
        }
    }
}

fn apply_codex_waiting(
    codex: &mut HashMap<String, SessionEntry>,
    last_message: &HashMap<String, LastMessage>,
) {
    for entry in codex.values_mut() {
        if entry.state != "idle" {
            continue;
        }
        if let Some(message) = last_message.get(&entry.session_id) {
            if message.role == "assistant" && message.text.trim_end().ends_with('?') {
                entry.state = "waiting".to_string();
            }
        }
    }
}

fn extract_assistant_text(payload: &serde_json::Value) -> Option<String> {
    let content = payload.get("content")?.as_array()?;
    let mut last_text: Option<String> = None;
    for item in content {
        let item_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if item_type == "text" || item_type == "output_text" || item_type == "input_text" {
            if let Some(text) = item.get("text").and_then(|v| v.as_str()) {
                last_text = Some(text.to_string());
            }
        }
    }
    last_text
}

fn debug_enabled() -> bool {
    env::args().any(|arg| arg == "--debug" || arg == "--debug-only")
}

fn debug_only() -> bool {
    env::args().any(|arg| arg == "--debug-only")
}

fn debug_log(message: &str) {
    if debug_enabled() {
        eprintln!("{message}");
    }
}

fn list_windows() -> Vec<WindowRow> {
    let output = Command::new("tmux")
        .args([
            "list-windows",
            "-a",
            "-F",
            "#{session_name}:#{window_index}\t#{window_id}\t#{window_name}\t#{pane_current_path}\t#{pane_current_command}",
        ])
        .output()
        .ok();

    let output = match output {
        Some(output) if output.status.success() => output,
        _ => return Vec::new(),
    };

    let mut rows = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 5 {
            continue;
        }
        let session_index = parts[0].to_string();
        let session_name = parts[0].split(':').next().unwrap_or("").to_string();
        if session_name.starts_with("drawer-") {
            continue;
        }
        rows.push(WindowRow {
            session_name,
            session_index,
            window_id: parts[1].to_string(),
            window_name: parts[2].to_string(),
            pane_path: parts[3].to_string(),
            pane_command: parts[4].to_string(),
        });
    }
    rows
}

fn filter_windows(rows: &[WindowRow]) -> Vec<WindowRow> {
    rows.iter()
        .filter(|row| row.session_name != "dev" && row.session_name != "scratch")
        .cloned()
        .collect()
}

fn sorted_sessions(rows: &[WindowRow], order: &[String]) -> Vec<String> {
    let mut sessions = Vec::new();
    let mut seen = HashSet::new();
    for row in rows {
        if seen.insert(row.session_name.clone()) {
            sessions.push(row.session_name.clone());
        }
    }

    let mut sorted = Vec::new();
    for preferred in order {
        if sessions.iter().any(|name| name == preferred) {
            sorted.push(preferred.clone());
        }
    }
    for session in sessions {
        if !sorted.iter().any(|name| name == &session) {
            sorted.push(session);
        }
    }
    sorted
}

fn key_to_index(key: char) -> i32 {
    KEYS.iter()
        .position(|&k| k == key)
        .map(|v| v as i32)
        .unwrap_or(-1)
}

fn status_for_window(
    row: &WindowRow,
    claude_by_tmux: &HashMap<String, SessionEntry>,
    codex_by_cwd: &HashMap<String, SessionEntry>,
) -> Option<String> {
    if let Some(entry) = claude_by_tmux.get(&row.window_id) {
        return Some(format_status(entry.state.as_str(), false));
    }

    let has_codex_command = row.pane_command.contains("codex");
    let has_codex_name = row.window_name.contains("codex");
    if !has_codex_command && !has_codex_name {
        return None;
    }

    match_by_cwd(row, codex_by_cwd).map(|entry| format_status(entry.state.as_str(), true))
}

fn format_status(state: &str, codex: bool) -> String {
    let label = if codex {
        match state {
            "responding" => "[working]",
            "waiting" => "[waiting]",
            "idle" => "[idle]",
            _ => "[?]",
        }
    } else {
        match state {
            "waiting" => "[waiting]",
            "responding" => "[working]",
            "idle" => "[idle]",
            _ => "[?]",
        }
    };

    let color = if codex {
        match state {
            "responding" => "\x1b[34m",
            "waiting" => "\x1b[1;33m",
            "idle" => "\x1b[90m",
            _ => "\x1b[90m",
        }
    } else {
        match state {
            "waiting" => "\x1b[1;33m",
            "responding" => "\x1b[34m",
            "idle" => "\x1b[90m",
            _ => "\x1b[90m",
        }
    };

    format!("{color}{label}\x1b[0m")
}

fn match_by_cwd<'a>(
    row: &WindowRow,
    entries: &'a HashMap<String, SessionEntry>,
) -> Option<&'a SessionEntry> {
    let mut best: Option<(&SessionEntry, usize)> = None;
    for (cwd, entry) in entries.iter() {
        if !should_match_cwd(&row.pane_path, cwd) {
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

fn path_depth(path: &str) -> usize {
    Path::new(path)
        .components()
        .filter(|c| !matches!(c, std::path::Component::RootDir))
        .count()
}

fn should_match_cwd(pane_path: &str, cwd: &str) -> bool {
    if cwd.is_empty() || cwd == "/" {
        return false;
    }
    if let Some(home) = dirs::home_dir() {
        if cwd == home.to_string_lossy() {
            return false;
        }
    }
    let pane = Path::new(pane_path);
    let cwd_path = Path::new(cwd);
    if !pane.starts_with(cwd_path) {
        return false;
    }
    true
}

fn format_window_line(row: &WindowRow, status: Option<String>) -> String {
    if let Some(status) = status {
        format!("{} {} {}", row.session_index, status, row.window_name)
    } else {
        format!("{} {}", row.session_index, row.window_name)
    }
}

fn terminal_lines() -> usize {
    if env::var("TMUX").is_ok() {
        if let Ok(output) = Command::new("tmux")
            .args(["display-message", "-p", "#{pane_height}"])
            .output()
        {
            if output.status.success() {
                if let Ok(value) = String::from_utf8(output.stdout) {
                    if let Ok(lines) = value.trim().parse::<usize>() {
                        return lines;
                    }
                }
            }
        }
    }

    if let Ok(output) = Command::new("tput").arg("lines").output() {
        if output.status.success() {
            if let Ok(value) = String::from_utf8(output.stdout) {
                return value.trim().parse::<usize>().unwrap_or(24);
            }
        }
    }
    24
}

fn print_clear(tty: &mut Option<Tty>) {
    if let Some(tty) = tty.as_mut() {
        tty.write_all("\x1b[2J\x1b[H");
        tty.flush();
        return;
    }
    print!("\x1b[2J\x1b[H");
    let _ = io::stdout().flush();
}

fn run_fzf_search(rows: &[WindowRow]) {
    let mut input = String::new();
    for row in rows {
        input.push_str(&format!(
            "{} {} {}\n",
            row.session_index, row.window_id, row.window_name
        ));
    }

    let mut fzf = match Command::new("fzf")
        .args([
            "--no-border",
            "--height=100%",
            "--with-nth=1,3..",
            "--header=Type to search, Enter to select",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return,
    };

    if let Some(mut stdin) = fzf.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }

    let output = match fzf.wait_with_output() {
        Ok(output) => output,
        Err(_) => return,
    };

    if !output.status.success() {
        return;
    }

    let selected = String::from_utf8_lossy(&output.stdout);
    let target = selected.split_whitespace().next().unwrap_or("");
    if target.is_empty() {
        return;
    }

    let _ = Command::new("tmux")
        .args(["switch-client", "-t", target])
        .status();
}

fn build_claude_map(sessions: &[SessionEntry]) -> HashMap<String, SessionEntry> {
    sessions
        .iter()
        .filter(|entry| entry.source == "claude")
        .filter_map(|entry| {
            entry
                .tmux_window_id
                .as_ref()
                .map(|id| (id.clone(), entry.clone()))
        })
        .collect()
}

fn build_codex_map(sessions: &[SessionEntry]) -> HashMap<String, SessionEntry> {
    sessions
        .iter()
        .filter(|entry| entry.source == "codex")
        .filter_map(|entry| entry.cwd.as_ref().map(|cwd| (cwd.clone(), entry.clone())))
        .collect()
}

enum ScreenState {
    Sessions,
    Windows {
        target_session: String,
        session_windows: Vec<WindowRow>,
    },
}

fn render_sessions_screen(
    tty: &mut Option<Tty>,
    sessions: &[String],
    windows: &[WindowRow],
    claude_by_tmux: &HashMap<String, SessionEntry>,
    codex_by_cwd: &HashMap<String, SessionEntry>,
) {
    print_clear(tty);
    let header = "h/j/k/l = select session | / = search | q/Esc = cancel\n\n";
    if let Some(tty) = tty.as_mut() {
        tty.write_all(header);
    } else {
        print!("{header}");
    }

    let max_lines = terminal_lines().saturating_sub(3);
    let mut line_count = 0usize;

    for (sidx, session) in sessions.iter().enumerate() {
        let skey = if sidx < KEYS.len() { KEYS[sidx] } else { '?' };
        for (widx, row) in windows
            .iter()
            .filter(|row| &row.session_name == session)
            .enumerate()
        {
            if line_count >= max_lines {
                break;
            }
            let wkey = if widx < KEYS.len() { KEYS[widx] } else { '?' };
            if debug_enabled() {
                debug_log(&format!(
                    "window: {}:{} id={} path={}",
                    row.session_name, row.session_index, row.window_id, row.pane_path
                ));
            }
            let status = status_for_window(row, claude_by_tmux, codex_by_cwd);
            let line = format_window_line(row, status);
            if let Some(tty) = tty.as_mut() {
                tty.write_all(&format!("\x1b[33m[{skey}{wkey}]\x1b[0m {line}\n"));
            } else {
                println!("\x1b[33m[{skey}{wkey}]\x1b[0m {line}");
            }
            line_count += 1;
        }
    }
    if let Some(tty) = tty.as_mut() {
        tty.flush();
    } else {
        let _ = io::stdout().flush();
    }
}

fn render_windows_screen(
    tty: &mut Option<Tty>,
    target_session: &str,
    windows: &[WindowRow],
    claude_by_tmux: &HashMap<String, SessionEntry>,
    codex_by_cwd: &HashMap<String, SessionEntry>,
) -> Vec<WindowRow> {
    print_clear(tty);
    if let Some(tty) = tty.as_mut() {
        tty.write_all("h/j/k/l = select window | q/Esc = cancel\n\n");
        tty.write_all(&format!("\x1b[36mSession: {target_session}\x1b[0m\n\n"));
    } else {
        println!("h/j/k/l = select window | q/Esc = cancel");
        println!();
        println!("\x1b[36mSession: {target_session}\x1b[0m");
        println!();
    }

    let mut session_windows = Vec::new();
    for (widx, row) in windows
        .iter()
        .filter(|row| row.session_name == target_session)
        .enumerate()
    {
        session_windows.push(row.clone());
        let wkey = if widx < KEYS.len() { KEYS[widx] } else { '?' };
        let status = status_for_window(row, claude_by_tmux, codex_by_cwd);
        let line = format_window_line(row, status);
        if let Some(tty) = tty.as_mut() {
            tty.write_all(&format!("\x1b[33m[{wkey}]\x1b[0m {line}\n"));
        } else {
            println!("\x1b[33m[{wkey}]\x1b[0m {line}");
        }
    }
    if let Some(tty) = tty.as_mut() {
        tty.flush();
    } else {
        let _ = io::stdout().flush();
    }

    session_windows
}

fn main() {
    if !debug_enabled() && env::var("TMUX").is_err() {
        eprintln!("tmux-fzf-switcher must run inside tmux");
        return;
    }

    if env::args().any(|arg| arg == "--fzf") {
        let all_windows = list_windows();
        if all_windows.is_empty() {
            eprintln!("No tmux windows found");
            return;
        }
        run_fzf_search(&all_windows);
        return;
    }

    let mut tty_out = Tty::open();

    let all_windows = list_windows();
    let windows = filter_windows(&all_windows);
    if windows.is_empty() {
        eprintln!("No tmux windows found");
        return;
    }

    let session_order = load_session_order();
    let sessions = sorted_sessions(&windows, &session_order);

    let active_sessions = load_sessions();
    let claude_by_tmux = build_claude_map(&active_sessions);
    let mut codex_by_cwd: HashMap<String, SessionEntry> = HashMap::new();
    if debug_enabled() {
        debug_log(&format!("active sessions: {}", active_sessions.len()));
        if !session_order.is_empty() {
            debug_log(&format!("session order: {}", session_order.join(",")));
        }
        debug_log(&format!("sorted sessions: {}", sessions.join(",")));
        let mut source_counts: HashMap<String, usize> = HashMap::new();
        for entry in &active_sessions {
            *source_counts.entry(entry.source.clone()).or_insert(0) += 1;
        }
        for (source, count) in source_counts {
            debug_log(&format!("source count: {source}={count}"));
        }
        debug_log(&format!("claude tmux count: {}", claude_by_tmux.len()));
        for key in claude_by_tmux.keys() {
            debug_log(&format!("claude tmux id: {key}"));
        }
        for row in &windows {
            debug_log(&format!(
                "window: {}:{} id={} path={} cmd={} name={}",
                row.session_name,
                row.session_index,
                row.window_id,
                row.pane_path,
                row.pane_command,
                row.window_name
            ));
        }
    }

    if debug_only() {
        return;
    }

    let _raw = match enable_raw_mode() {
        Some(guard) => guard,
        None => {
            eprintln!("Failed to enable raw mode");
            return;
        }
    };

    let (key_tx, key_rx) = mpsc::channel::<char>();
    thread::spawn(move || {
        let mut tty_in = Tty::open();
        while let Some(key) = read_key(true, &mut tty_in) {
            if key_tx.send(key).is_err() {
                break;
            }
        }
    });

    let (codex_tx, codex_rx) = mpsc::channel::<HashMap<String, SessionEntry>>();
    thread::spawn(move || {
        let codex_sessions = load_codex_sessions();
        let _ = codex_tx.send(codex_sessions);
    });

    let mut codex_loaded = false;
    let mut screen = ScreenState::Sessions;
    render_sessions_screen(
        &mut tty_out,
        &sessions,
        &windows,
        &claude_by_tmux,
        &codex_by_cwd,
    );

    loop {
        if !codex_loaded {
            if let Ok(codex_sessions) = codex_rx.try_recv() {
                let codex_vec: Vec<SessionEntry> = codex_sessions.values().cloned().collect();
                codex_by_cwd = build_codex_map(&codex_vec);
                codex_loaded = true;
                if debug_enabled() {
                    debug_log(&format!("codex sessions: {}", codex_sessions.len()));
                    for (cwd, entry) in &codex_by_cwd {
                        debug_log(&format!(
                            "codex: session={} state={} cwd={}",
                            entry.session_id, entry.state, cwd
                        ));
                    }
                }
                let target_session = match &screen {
                    ScreenState::Sessions => {
                        render_sessions_screen(
                            &mut tty_out,
                            &sessions,
                            &windows,
                            &claude_by_tmux,
                            &codex_by_cwd,
                        );
                        None
                    }
                    ScreenState::Windows { target_session, .. } => Some(target_session.clone()),
                };
                if let Some(target_session) = target_session {
                    let session_windows = render_windows_screen(
                        &mut tty_out,
                        &target_session,
                        &windows,
                        &claude_by_tmux,
                        &codex_by_cwd,
                    );
                    screen = ScreenState::Windows {
                        target_session,
                        session_windows,
                    };
                }
            }
        }

        let key = match key_rx.recv_timeout(Duration::from_millis(50)) {
            Ok(key) => key,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
        };

        match &mut screen {
            ScreenState::Sessions => {
                if key == '/' {
                    drop(_raw);
                    if let Ok(exe) = env::current_exe() {
                        let err = Command::new(exe).arg("--fzf").exec();
                        eprintln!("Failed to exec fzf mode: {err}");
                    }
                    run_fzf_search(&all_windows);
                    return;
                }

                if key == 'q' || key == 27 as char {
                    return;
                }

                let session_idx = key_to_index(key);
                if session_idx < 0 || session_idx as usize >= sessions.len() {
                    eprintln!("Invalid session key: {key}");
                    return;
                }

                let target_session = sessions[session_idx as usize].clone();
                let session_windows = render_windows_screen(
                    &mut tty_out,
                    &target_session,
                    &windows,
                    &claude_by_tmux,
                    &codex_by_cwd,
                );
                screen = ScreenState::Windows {
                    target_session,
                    session_windows,
                };
            }
            ScreenState::Windows {
                session_windows, ..
            } => {
                if key == 'q' || key == 27 as char {
                    return;
                }

                let window_idx = key_to_index(key);
                if window_idx < 0 {
                    eprintln!("Invalid window key: {key}");
                    return;
                }

                let window_idx = window_idx as usize;
                let target = session_windows
                    .get(window_idx)
                    .map(|row| row.session_index.clone())
                    .unwrap_or_default();
                if target.is_empty() {
                    eprintln!("Window not found");
                    return;
                }

                let _ = Command::new("tmux")
                    .args(["switch-client", "-t", &target])
                    .status();
                return;
            }
        }
    }
}
