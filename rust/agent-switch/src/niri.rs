use crate::daemon::{
    self, AgentSession, AgentState, CodexSession, DaemonMessage, SessionCache, TrackEvent,
};
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
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;

const APP_ID: &str = "com.thrawny.agent-switch";
const KEYS: [char; 8] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p'];

// Use DaemonMessage as base, add niri-specific ReloadConfig
#[derive(Debug)]
enum NiriMessage {
    Daemon(DaemonMessage),
    ReloadConfig,
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
    daemon::match_codex_by_dir(&dir, codex_by_cwd).map(|entry| entry.state)
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
    let path = daemon::socket_path();
    let mut stream = UnixStream::connect(&path)?;
    stream.write_all(b"toggle")?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(())
}

fn start_config_watcher(tx: mpsc::Sender<NiriMessage>) {
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
                                let _ = tx_clone.send(NiriMessage::ReloadConfig);
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
                log::error!("Failed to create config watcher: {}", e);
                return;
            }
        };

        if let Some(dir) = config_dir {
            if let Err(e) = watcher.watch(&dir, RecursiveMode::NonRecursive) {
                log::error!("Failed to watch config directory: {}", e);
                return;
            }
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        }
    });
}

fn start_focus_tracker(focused_window: Arc<Mutex<Option<u64>>>) {
    thread::spawn(move || {
        loop {
            let mut socket = match Socket::connect() {
                Ok(s) => s,
                Err(e) => {
                    log::error!("Failed to connect to niri: {}", e);
                    thread::sleep(std::time::Duration::from_secs(1));
                    continue;
                }
            };

            match socket.send(Request::EventStream) {
                Ok(Ok(Response::Handled)) => {}
                Ok(Ok(_)) => {}
                result => {
                    log::error!("Failed to request event stream: {:?}", result);
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
    rx: mpsc::Receiver<NiriMessage>,
    focused_window: Arc<Mutex<Option<u64>>>,
    cache: Arc<Mutex<SessionCache>>,
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
    let codex_sessions = {
        let cache = cache.lock().unwrap();
        cache.codex_sessions.clone()
    };

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
    let cache_for_poll = cache.clone();

    glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
        while let Ok(msg) = rx.try_recv() {
            match msg {
                NiriMessage::Daemon(DaemonMessage::Toggle) => {
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
                        state.codex_sessions = {
                            let cache = cache_for_poll.lock().unwrap();
                            cache.codex_sessions.clone()
                        };
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
                NiriMessage::ReloadConfig => {
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
                NiriMessage::Daemon(DaemonMessage::SessionsChanged) => {
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
                NiriMessage::Daemon(DaemonMessage::CodexChanged) => {
                    let mut state = state_for_poll.borrow_mut();
                    state.codex_sessions = {
                        let cache = cache_for_poll.lock().unwrap();
                        cache.codex_sessions.clone()
                    };
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
                NiriMessage::Daemon(DaemonMessage::Track(event)) => {
                    let focused_id = *focused_window_for_poll.lock().unwrap();
                    handle_track_event(&event, focused_id);
                }
                NiriMessage::Daemon(DaemonMessage::List(_)) => {
                    // Handled by socket listener directly
                }
                NiriMessage::Daemon(DaemonMessage::Shutdown) => {
                    // Exit GTK app
                    std::process::exit(0);
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

/// Run the niri daemon with GTK overlay (new `serve --niri` mode)
pub fn run_with_daemon() -> glib::ExitCode {
    let (daemon_tx, daemon_rx) = mpsc::channel::<DaemonMessage>();
    let (niri_tx, niri_rx) = mpsc::channel::<NiriMessage>();
    let cache = Arc::new(Mutex::new(SessionCache::new()));
    let focused_window: Arc<Mutex<Option<u64>>> = Arc::new(Mutex::new(None));

    // Initial load
    {
        let mut cache = cache.lock().unwrap();
        cache.reload_agent_sessions();
        cache.reload_codex_sessions();
    }

    log::info!(
        "Starting niri daemon with overlay, listening on {:?}",
        daemon::socket_path()
    );

    // Start daemon threads (socket listener, file watchers)
    daemon::start_socket_listener(daemon_tx.clone(), cache.clone());
    daemon::start_sessions_watcher(daemon_tx.clone());
    daemon::start_codex_poller(daemon_tx.clone());

    // Start niri-specific threads
    start_config_watcher(niri_tx.clone());
    start_focus_tracker(focused_window.clone());

    // Bridge daemon messages to niri message channel
    let niri_tx_clone = niri_tx.clone();
    let cache_clone = cache.clone();
    thread::spawn(move || {
        loop {
            let msg = match daemon_rx.recv() {
                Ok(msg) => msg,
                Err(_) => break,
            };

            // Handle cache updates for daemon messages
            match &msg {
                DaemonMessage::SessionsChanged => {
                    let mut cache = cache_clone.lock().unwrap();
                    cache.reload_agent_sessions();
                }
                DaemonMessage::CodexChanged => {
                    let mut cache = cache_clone.lock().unwrap();
                    cache.reload_codex_sessions();
                }
                _ => {}
            }

            // Forward to GTK thread
            if niri_tx_clone.send(NiriMessage::Daemon(msg)).is_err() {
                break;
            }
        }
    });

    let rx = Rc::new(RefCell::new(Some(niri_rx)));
    let focused_window_rc = Rc::new(RefCell::new(Some(focused_window)));
    let cache_rc = Rc::new(RefCell::new(Some(cache)));

    let app = Application::builder()
        .application_id(APP_ID)
        .flags(gtk4::gio::ApplicationFlags::NON_UNIQUE)
        .build();

    let rx_clone = rx.clone();
    let focused_clone = focused_window_rc.clone();
    let cache_clone = cache_rc.clone();
    app.connect_activate(move |app| {
        if let (Some(rx), Some(focused), Some(cache)) = (
            rx_clone.borrow_mut().take(),
            focused_clone.borrow_mut().take(),
            cache_clone.borrow_mut().take(),
        ) {
            build_ui(app, rx, focused, cache);
        }
    });

    app.run_with_args::<&str>(&[])
}

/// Legacy run function for backward compatibility (`niri --toggle` and standalone daemon)
pub fn run(toggle: bool) -> glib::ExitCode {
    if toggle {
        if let Err(e) = send_toggle() {
            log::error!("Failed to toggle: {} (is daemon running?)", e);
            std::process::exit(1);
        }
        std::process::exit(0);
    }

    // Legacy mode: run standalone with its own socket listener
    run_with_daemon()
}
