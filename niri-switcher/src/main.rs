use clap::Parser;
use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, Box as GtkBox, Label, Orientation};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;

const APP_ID: &str = "com.thrawny.niri-switcher";
const KEYS: [char; 8] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p'];

#[derive(Debug, Clone, PartialEq)]
enum ClaudeState {
    Waiting,    // Needs user attention (permission prompt)
    Responding, // Actively working
    Idle,       // Finished, no action needed
    Unknown,
}

impl ClaudeState {
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
}

#[derive(Debug, Clone)]
struct ClaudeSession {
    transcript_path: PathBuf,
    state: ClaudeState,
}

#[derive(Debug)]
enum Message {
    Toggle,
    ReloadConfig,
    ClaudeSessionsChanged,
    ClaudeActivity { window_id: u64 },
}

fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("projects.toml")
}

#[derive(Parser)]
#[command(name = "niri-switcher", about = "Project switcher for niri")]
struct Cli {
    /// Toggle visibility of the switcher (send command to running daemon)
    #[arg(long)]
    toggle: bool,
}

fn socket_path() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("niri-switcher.sock")
}

#[derive(Debug, Clone, Deserialize)]
struct Project {
    key: String,
    name: String,
    dir: String,
    /// If true, this is a static named workspace defined in niri config.
    /// It always exists and we just focus it (spawning terminals if empty).
    #[serde(default)]
    static_workspace: bool,
}

#[derive(Debug, Clone)]
struct WorkspaceColumn {
    workspace_name: String,
    workspace_key: char,
    column_index: u32,
    column_key: char,
    app_label: String,
    dir: String,
    static_workspace: bool,
    window_id: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct Config {
    project: Vec<Project>,
}

struct AppState {
    projects: Vec<Project>,
    entries: Vec<WorkspaceColumn>,
    pending_key: Option<char>,
    claude_sessions: HashMap<u64, ClaudeSession>,
}

fn load_projects() -> Vec<Project> {
    if let Ok(content) = std::fs::read_to_string(config_path()) {
        if let Ok(config) = toml::from_str::<Config>(&content) {
            return config.project;
        }
    }

    // Default projects
    vec![Project {
        key: "h".to_string(),
        name: "dotfiles".to_string(),
        dir: "~/dotfiles".to_string(),
        static_workspace: true,
    }]
}

fn niri_cmd(args: &[&str]) -> Option<String> {
    let output = Command::new("niri")
        .arg("msg")
        .args(args)
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

fn niri_json(args: &[&str]) -> Option<serde_json::Value> {
    let output = Command::new("niri")
        .arg("msg")
        .arg("--json")
        .args(args)
        .output()
        .ok()?;
    serde_json::from_slice(&output.stdout).ok()
}

fn get_workspace_by_name(name: &str) -> Option<serde_json::Value> {
    let workspaces = niri_json(&["workspaces"])?;
    workspaces
        .as_array()?
        .iter()
        .find(|ws| ws.get("name").and_then(|n| n.as_str()) == Some(name))
        .cloned()
}

fn workspace_has_windows(name: &str) -> bool {
    let Some(ws) = get_workspace_by_name(name) else {
        return false;
    };
    let Some(ws_id) = ws.get("id").and_then(|id| id.as_i64()) else {
        return false;
    };
    let Some(windows) = niri_json(&["windows"]) else {
        return false;
    };
    windows
        .as_array()
        .map(|arr| {
            arr.iter()
                .any(|w| w.get("workspace_id").and_then(|id| id.as_i64()) == Some(ws_id))
        })
        .unwrap_or(false)
}

fn simplify_label(title: &str, app_id: &str) -> String {
    // Prefer title for terminals since it shows what's running
    if app_id.contains("ghostty") || app_id.contains("terminal") || app_id.contains("alacritty") {
        // Detect Claude sessions by ✳ marker
        if title.starts_with('✳') {
            let desc = title.trim_start_matches('✳').trim();
            return format!("claude: {}", desc);
        }
        // Clean up title - remove common markers
        let cleaned = title
            .trim_start_matches(['●', '○', ' '].as_ref())
            .trim();
        // If title is just a path, take the last component
        if cleaned.starts_with('/') || cleaned.starts_with('~') {
            cleaned.split('/').last().unwrap_or(cleaned).to_string()
        } else {
            // Take first word for things like "nvim foo.rs"
            cleaned.split_whitespace().next().unwrap_or(cleaned).to_string()
        }
    } else {
        // For non-terminals, use simplified app_id
        app_id.split('.').last().unwrap_or(app_id).to_string()
    }
}

fn get_workspace_columns(projects: &[Project]) -> Vec<WorkspaceColumn> {
    let workspaces = niri_json(&["workspaces"]).unwrap_or_default();
    let windows = niri_json(&["windows"]).unwrap_or_default();
    let windows_arr = windows.as_array().map(|a| a.as_slice()).unwrap_or(&[]);

    let mut entries = Vec::new();

    for (proj_idx, project) in projects.iter().enumerate() {
        if proj_idx >= KEYS.len() {
            break;
        }
        let workspace_key = KEYS[proj_idx];

        let ws = workspaces
            .as_array()
            .and_then(|arr| {
                arr.iter()
                    .find(|ws| ws.get("name").and_then(|n| n.as_str()) == Some(&project.name))
            });

        let ws_id = ws.and_then(|w| w.get("id").and_then(|id| id.as_i64()));

        // Group windows by column index
        let mut columns: std::collections::BTreeMap<i64, Vec<&serde_json::Value>> =
            std::collections::BTreeMap::new();

        if let Some(ws_id) = ws_id {
            for window in windows_arr {
                let window_ws_id = window.get("workspace_id").and_then(|id| id.as_i64());
                if window_ws_id != Some(ws_id) {
                    continue;
                }
                let col_idx = window
                    .get("layout")
                    .and_then(|l| l.get("pos_in_scrolling_layout"))
                    .and_then(|p| p.get(0))
                    .and_then(|c| c.as_i64())
                    .unwrap_or(1);
                columns.entry(col_idx).or_default().push(window);
            }
        }

        // Skip column 1 (scratch), create entries for columns 2+
        let has_columns = columns.keys().any(|&idx| idx >= 2);

        if has_columns {
            for (&col_idx, col_windows) in &columns {
                if col_idx < 2 {
                    continue;
                }
                let key_offset = (col_idx - 2) as usize;
                if key_offset >= KEYS.len() {
                    continue;
                }
                let column_key = KEYS[key_offset];

                let first_window = col_windows.first();
                let title = first_window
                    .and_then(|w| w.get("title").and_then(|t| t.as_str()))
                    .unwrap_or("?");
                let app_id = first_window
                    .and_then(|w| w.get("app_id").and_then(|a| a.as_str()))
                    .unwrap_or("?");
                let window_id = first_window
                    .and_then(|w| w.get("id").and_then(|id| id.as_u64()));
                let app_label = simplify_label(title, app_id);

                entries.push(WorkspaceColumn {
                    workspace_name: project.name.clone(),
                    workspace_key,
                    column_index: col_idx as u32,
                    column_key,
                    app_label,
                    dir: project.dir.clone(),
                    static_workspace: project.static_workspace,
                    window_id,
                });
            }
        } else {
            // Empty workspace - add placeholder entry
            entries.push(WorkspaceColumn {
                workspace_name: project.name.clone(),
                workspace_key,
                column_index: 2,
                column_key: KEYS[0],
                app_label: "(empty)".to_string(),
                dir: project.dir.clone(),
                static_workspace: project.static_workspace,
                window_id: None,
            });
        }
    }

    entries
}

fn focus_workspace(name: &str) {
    niri_cmd(&["action", "focus-workspace", name]);
}

fn focus_column(index: u32) {
    niri_cmd(&["action", "focus-column", &index.to_string()]);
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

fn create_workspace(project: &Project) {
    let name = &project.name;

    if get_workspace_by_name(name).is_some() {
        niri_cmd(&["action", "focus-workspace", name]);
    } else {
        // Create new workspace
        if let Some(workspaces) = niri_json(&["workspaces"]) {
            if let Some(arr) = workspaces.as_array() {
                let max_idx = arr
                    .iter()
                    .filter_map(|ws| ws.get("idx").and_then(|i| i.as_i64()))
                    .max()
                    .unwrap_or(0);
                niri_cmd(&["action", "focus-workspace", &(max_idx + 1).to_string()]);
            }
        }
        niri_cmd(&["action", "set-workspace-name", name]);
    }

    std::thread::sleep(std::time::Duration::from_millis(100));
    spawn_terminals(&project.dir);
}

fn switch_to_project(project: &Project, column: u32) {
    if project.static_workspace {
        // Static workspace: always exists in niri config, just focus it
        focus_workspace(&project.name);
        // If empty, spawn terminals
        if !workspace_has_windows(&project.name) {
            spawn_terminals(&project.dir);
        }
    } else {
        // Dynamic workspace: create if doesn't exist
        if !workspace_has_windows(&project.name) {
            create_workspace(project);
        }
        focus_workspace(&project.name);
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    focus_column(column);
}

fn switch_to_entry(entry: &WorkspaceColumn) {
    if entry.static_workspace {
        focus_workspace(&entry.workspace_name);
        if entry.app_label == "(empty)" {
            spawn_terminals(&entry.dir);
        }
    } else {
        if entry.app_label == "(empty)" {
            // Create a temporary Project to use create_workspace
            let project = Project {
                key: entry.workspace_key.to_string(),
                name: entry.workspace_name.clone(),
                dir: entry.dir.clone(),
                static_workspace: false,
            };
            create_workspace(&project);
        }
        focus_workspace(&entry.workspace_name);
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

    // Remove existing socket
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
                    let mut buf = [0u8; 64];
                    if let Ok(_n) = stream.read(&mut buf) {
                        let _ = tx.send(Message::Toggle);
                        let _ = stream.write_all(b"ok");
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
                    // Only reload on modify/create events for our config file
                    let dominated_by_config = event.paths.iter().any(|p| {
                        p.file_name() == config_filename.as_deref()
                    });
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
            // Keep watcher alive
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        }
    });
}

fn claude_sessions_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".claude")
        .join("active-sessions.json")
}

fn load_claude_sessions_file() -> HashMap<u64, ClaudeSession> {
    let path = claude_sessions_path();
    if !path.exists() {
        return HashMap::new();
    }

    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return HashMap::new(),
    };

    let json: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return HashMap::new(),
    };

    let mut sessions = HashMap::new();
    if let Some(obj) = json.as_object() {
        for (window_id_str, session_data) in obj {
            if let Ok(window_id) = window_id_str.parse::<u64>() {
                if let Some(transcript_path) = session_data
                    .get("transcript_path")
                    .and_then(|p| p.as_str())
                {
                    let state = session_data
                        .get("state")
                        .and_then(|s| s.as_str())
                        .map(ClaudeState::from_str)
                        .unwrap_or(ClaudeState::Unknown);
                    sessions.insert(window_id, ClaudeSession {
                        transcript_path: PathBuf::from(transcript_path),
                        state,
                    });
                }
            }
        }
    }
    sessions
}

fn start_claude_watcher(tx: mpsc::Sender<Message>) {
    let claude_dir = dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".claude");

    // Shared state: transcript path -> window_id mapping
    let transcript_map: Arc<Mutex<HashMap<PathBuf, u64>>> = Arc::new(Mutex::new(HashMap::new()));

    thread::spawn(move || {
        let tx_sessions = tx.clone();
        let tx_activity = tx.clone();
        let transcript_map_for_sessions = transcript_map.clone();
        let transcript_map_for_activity = transcript_map.clone();

        // Watcher for active-sessions.json changes
        let mut sessions_watcher = match RecommendedWatcher::new(
            move |res: Result<notify::Event, notify::Error>| {
                if let Ok(event) = res {
                    let is_sessions_file = event.paths.iter().any(|p| {
                        p.file_name()
                            .map(|f| f == "active-sessions.json")
                            .unwrap_or(false)
                    });
                    if is_sessions_file {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                // Update transcript map
                                let sessions = load_claude_sessions_file();
                                let mut map = transcript_map_for_sessions.lock().unwrap();
                                map.clear();
                                for (window_id, session) in sessions {
                                    map.insert(session.transcript_path, window_id);
                                }
                                let _ = tx_sessions.send(Message::ClaudeSessionsChanged);
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
                eprintln!("Failed to create claude sessions watcher: {}", e);
                return;
            }
        };

        // Watcher for transcript file modifications
        let mut transcript_watcher = match RecommendedWatcher::new(
            move |res: Result<notify::Event, notify::Error>| {
                if let Ok(event) = res {
                    match event.kind {
                        notify::EventKind::Modify(_) => {
                            let map = transcript_map_for_activity.lock().unwrap();
                            for path in &event.paths {
                                if let Some(&window_id) = map.get(path) {
                                    let _ = tx_activity.send(Message::ClaudeActivity { window_id });
                                }
                            }
                        }
                        _ => {}
                    }
                }
            },
            notify::Config::default(),
        ) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("Failed to create transcript watcher: {}", e);
                return;
            }
        };

        // Watch ~/.claude directory for active-sessions.json
        if claude_dir.exists() {
            if let Err(e) = sessions_watcher.watch(&claude_dir, RecursiveMode::NonRecursive) {
                eprintln!("Failed to watch claude directory: {}", e);
                return;
            }
        }

        // Watch ~/.claude/projects recursively for transcript files
        let projects_dir = claude_dir.join("projects");
        if projects_dir.exists() {
            if let Err(e) = transcript_watcher.watch(&projects_dir, RecursiveMode::Recursive) {
                eprintln!("Failed to watch claude projects directory: {}", e);
            }
        }

        // Initial load of sessions
        let sessions = load_claude_sessions_file();
        {
            let mut map = transcript_map.lock().unwrap();
            for (window_id, session) in sessions {
                map.insert(session.transcript_path, window_id);
            }
        }
        let _ = tx.send(Message::ClaudeSessionsChanged);

        // Keep watchers alive
        loop {
            std::thread::sleep(std::time::Duration::from_secs(3600));
        }
    });
}

fn build_ui(app: &Application, rx: mpsc::Receiver<Message>) {
    let window = ApplicationWindow::builder()
        .application(app)
        .default_width(400)
        .build();

    // Layer shell setup
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_anchor(Edge::Top, false);
    window.set_anchor(Edge::Bottom, false);
    window.set_anchor(Edge::Left, false);
    window.set_anchor(Edge::Right, false);

    let projects = load_projects();
    let entries = get_workspace_columns(&projects);

    // Initialize Claude sessions from file
    let claude_sessions = load_claude_sessions_file();

    let state = Rc::new(RefCell::new(AppState {
        projects,
        entries,
        pending_key: None,
        claude_sessions,
    }));

    // Outer box for border (GTK4 windows don't render borders properly)
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
            &state_ref.claude_sessions,
        );
    }
    outer_box.append(&main_box);

    // CSS
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
            color: #81a2be;
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

    // Key controller
    let key_controller = gtk4::EventControllerKey::new();
    let state_clone = state.clone();
    let window_clone = window.clone();
    let main_box_clone = main_box.clone();

    key_controller.connect_key_pressed(move |_, keyval, _, _| {
        let key_name = keyval.name().map(|s| s.to_lowercase());
        let Some(key) = key_name.as_deref() else {
            return glib::Propagation::Proceed;
        };

        // Cancel - hide or clear pending key
        if key == "q" || key == "escape" {
            let mut state = state_clone.borrow_mut();
            if state.pending_key.is_some() {
                // Clear pending key and show full list
                state.pending_key = None;
                let entries = state.entries.clone();
                let claude_sessions = state.claude_sessions.clone();
                drop(state);
                build_entry_list(&main_box_clone, &entries, None, &claude_sessions);
            } else {
                // Hide window
                drop(state);
                window_clone.set_visible(false);
            }
            return glib::Propagation::Stop;
        }

        // Handle key input
        if let Some(pos) = KEYS.iter().position(|&k| k.to_string() == key) {
            let key_char = KEYS[pos];
            let mut state = state_clone.borrow_mut();

            if let Some(first_key) = state.pending_key {
                // Second keystroke - find matching entry
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
                    // Invalid combo - reset
                    state.pending_key = None;
                    let entries = state.entries.clone();
                    let claude_sessions = state.claude_sessions.clone();
                    drop(state);
                    build_entry_list(&main_box_clone, &entries, None, &claude_sessions);
                }
            } else {
                // First keystroke - check if valid workspace key
                if state.entries.iter().any(|e| e.workspace_key == key_char) {
                    state.pending_key = Some(key_char);
                    let entries = state.entries.clone();
                    let claude_sessions = state.claude_sessions.clone();
                    drop(state);
                    build_entry_list(&main_box_clone, &entries, Some(key_char), &claude_sessions);
                }
            }
        }

        glib::Propagation::Stop
    });

    window.add_controller(key_controller);

    // Start hidden - will be shown via socket toggle
    window.set_visible(false);

    // Present once to initialize, then hide
    window.present();
    window.set_visible(false);

    // Poll message receiver
    let window_for_poll = window.clone();
    let state_for_poll = state.clone();
    let main_box_for_poll = main_box.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
        while let Ok(msg) = rx.try_recv() {
            match msg {
                Message::Toggle => {
                    let is_visible = window_for_poll.is_visible();
                    if is_visible {
                        // Hide and reset
                        window_for_poll.set_visible(false);
                        let mut state = state_for_poll.borrow_mut();
                        state.pending_key = None;
                    } else {
                        // Refresh entries from niri and show
                        let mut state = state_for_poll.borrow_mut();
                        state.entries = get_workspace_columns(&state.projects);
                        state.pending_key = None;
                        let entries = state.entries.clone();
                        let claude_sessions = state.claude_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, None, &claude_sessions);
                        window_for_poll.set_visible(true);
                        window_for_poll.present();
                    }
                }
                Message::ReloadConfig => {
                    // Reload projects from config file
                    let mut state = state_for_poll.borrow_mut();
                    state.projects = load_projects();
                    state.entries = get_workspace_columns(&state.projects);
                    // If visible, refresh the display
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let claude_sessions = state.claude_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, pending, &claude_sessions);
                    }
                }
                Message::ClaudeSessionsChanged => {
                    // Reload Claude sessions from file
                    let mut state = state_for_poll.borrow_mut();
                    state.claude_sessions = load_claude_sessions_file();
                    // If visible, refresh the display to show updated status
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let claude_sessions = state.claude_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, pending, &claude_sessions);
                    }
                }
                Message::ClaudeActivity { window_id: _ } => {
                    // Transcript file changed - reload sessions to get updated state
                    // The state is maintained by the hooks in active-sessions.json
                    let mut state = state_for_poll.borrow_mut();
                    state.claude_sessions = load_claude_sessions_file();
                    // If visible, refresh the display to show updated status
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let claude_sessions = state.claude_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, pending, &claude_sessions);
                    }
                }
            }
        }
        glib::ControlFlow::Continue
    });
}

fn build_entry_list(
    container: &GtkBox,
    entries: &[WorkspaceColumn],
    pending_key: Option<char>,
    claude_sessions: &HashMap<u64, ClaudeSession>,
) {
    // Clear
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

    // Filter entries if pending_key is set
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

        // Check if this is a Claude window and show state
        let app_label = if entry.app_label.starts_with("claude:") {
            if let Some(window_id) = entry.window_id {
                if let Some(session) = claude_sessions.get(&window_id) {
                    let desc = entry.app_label.trim_start_matches("claude:").trim();
                    format!("claude [{}]: {}", session.state.label(), desc)
                } else {
                    entry.app_label.clone()
                }
            } else {
                entry.app_label.clone()
            }
        } else {
            entry.app_label.clone()
        };

        let name_text = format!("{} / {}", entry.workspace_name, app_label);
        let name_label = Label::new(Some(&name_text));
        name_label.add_css_class("project");
        row.append(&name_label);

        container.append(&row);
    }
}

fn main() -> glib::ExitCode {
    let cli = Cli::parse();

    if cli.toggle {
        // Toggle mode: send command to daemon
        if let Err(e) = send_toggle() {
            eprintln!("Failed to toggle: {} (is daemon running?)", e);
            std::process::exit(1);
        }
        std::process::exit(0);
    }

    // Daemon mode: start GTK app with socket listener, config watcher, and claude watcher
    let (tx, rx) = mpsc::channel();
    start_socket_listener(tx.clone());
    start_config_watcher(tx.clone());
    start_claude_watcher(tx);

    let rx = Rc::new(RefCell::new(Some(rx)));

    let app = Application::builder()
        .application_id(APP_ID)
        .flags(gtk4::gio::ApplicationFlags::NON_UNIQUE)
        .build();

    let rx_clone = rx.clone();
    app.connect_activate(move |app| {
        if let Some(rx) = rx_clone.borrow_mut().take() {
            build_ui(app, rx);
        }
    });

    app.run()
}
