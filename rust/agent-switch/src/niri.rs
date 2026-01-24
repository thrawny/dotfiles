use crate::state;
use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box as GtkBox, Label, Orientation, glib};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use niri_ipc::{
    Action, Request, Response, Window, Workspace, WorkspaceReferenceArg, socket::Socket,
};
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
use std::thread;

const APP_ID: &str = "com.thrawny.agent-switch";
const KEYS: [char; 8] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p'];

#[derive(Debug, Clone, PartialEq)]
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

#[derive(Debug)]
enum Message {
    Toggle,
    ReloadConfig,
    SessionsChanged,
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
    dir: Option<String>,
    static_workspace: bool,
    window_id: Option<u64>,
}

struct AppState {
    config: Config,
    entries: Vec<WorkspaceColumn>,
    pending_key: Option<char>,
    agent_sessions: HashMap<u64, AgentSession>,
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
                let app_label = simplify_label(title, app_id);

                entries.push(WorkspaceColumn {
                    workspace_name: ws_name.to_string(),
                    workspace_ref: workspace_ref.clone(),
                    workspace_key,
                    column_index: col_idx as u32,
                    column_key,
                    app_label,
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
                    let mut buf = [0u8; 256];
                    if let Ok(count) = stream.read(&mut buf) {
                        if count > 0 {
                            let _ = tx.send(Message::Toggle);
                            let _ = stream.write_all(b"ok");
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
                    if is_state_file {
                        match event.kind {
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_) => {
                                let _ = tx_clone.send(Message::SessionsChanged);
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
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        }
    });
}

fn build_ui(app: &Application, rx: mpsc::Receiver<Message>) {
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

    let state = Rc::new(RefCell::new(AppState {
        config,
        entries,
        pending_key: None,
        agent_sessions,
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
                drop(state);
                build_entry_list(&main_box_clone, &entries, None, &agent_sessions);
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
                    drop(state);
                    build_entry_list(&main_box_clone, &entries, None, &agent_sessions);
                }
            } else {
                if state.entries.iter().any(|e| e.workspace_key == key_char) {
                    state.pending_key = Some(key_char);
                    let entries = state.entries.clone();
                    let agent_sessions = state.agent_sessions.clone();
                    drop(state);
                    build_entry_list(&main_box_clone, &entries, Some(key_char), &agent_sessions);
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
                        state.pending_key = None;
                        let entries = state.entries.clone();
                        let agent_sessions = state.agent_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, None, &agent_sessions);
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
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, pending, &agent_sessions);
                    }
                }
                Message::SessionsChanged => {
                    let mut state = state_for_poll.borrow_mut();
                    state.agent_sessions = load_agent_sessions();
                    if window_for_poll.is_visible() {
                        let entries = state.entries.clone();
                        let pending = state.pending_key;
                        let agent_sessions = state.agent_sessions.clone();
                        drop(state);
                        build_entry_list(&main_box_for_poll, &entries, pending, &agent_sessions);
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
    agent_sessions: &HashMap<u64, AgentSession>,
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
    start_socket_listener(tx.clone());
    start_config_watcher(tx.clone());
    start_sessions_watcher(tx);

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

    app.run_with_args::<&str>(&[])
}
