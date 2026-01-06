use clap::Parser;
use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, Box as GtkBox, Label, Orientation};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use serde::Deserialize;
use std::cell::RefCell;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;

const APP_ID: &str = "com.thrawny.niri-switcher";
const KEYS: [char; 8] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p'];

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
}

#[derive(Debug, Deserialize)]
struct Config {
    project: Vec<Project>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Stage {
    SelectProject,
    SelectColumn,
}

struct AppState {
    stage: Stage,
    selected_project: Option<Project>,
    projects: Vec<Project>,
}

fn load_projects() -> Vec<Project> {
    let config_path = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("projects.toml");

    if let Ok(content) = std::fs::read_to_string(&config_path) {
        if let Ok(config) = toml::from_str::<Config>(&content) {
            return config.project;
        }
    }

    // Default projects
    vec![
        Project {
            key: "h".to_string(),
            name: "dotfiles".to_string(),
            dir: "~/dotfiles".to_string(),
        },
        Project {
            key: "j".to_string(),
            name: "work".to_string(),
            dir: "~/work".to_string(),
        },
    ]
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

fn focus_workspace(name: &str) {
    niri_cmd(&["action", "focus-workspace", name]);
}

fn focus_column(index: u32) {
    niri_cmd(&["action", "focus-column", &index.to_string()]);
}

fn create_workspace(project: &Project) {
    let name = &project.name;
    let dir = shellexpand::tilde(&project.dir).to_string();

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

    // Spawn three ghostty terminals
    for _ in 0..3 {
        Command::new("ghostty")
            .arg(format!("--working-directory={}", dir))
            .spawn()
            .ok();
        std::thread::sleep(std::time::Duration::from_millis(300));
    }
}

fn switch_to_project(project: &Project, column: u32) {
    if !workspace_has_windows(&project.name) {
        create_workspace(project);
    }
    focus_workspace(&project.name);
    std::thread::sleep(std::time::Duration::from_millis(100));
    focus_column(column);
}

fn send_toggle() -> Result<(), Box<dyn std::error::Error>> {
    let path = socket_path();
    let mut stream = UnixStream::connect(&path)?;
    stream.write_all(b"toggle")?;
    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    Ok(())
}

fn start_socket_listener(tx: mpsc::Sender<String>) {
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
                    if let Ok(n) = stream.read(&mut buf) {
                        let cmd = String::from_utf8_lossy(&buf[..n]).to_string();
                        let _ = tx.send(cmd);
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

fn build_ui(app: &Application, rx: mpsc::Receiver<String>) {
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

    let state = Rc::new(RefCell::new(AppState {
        stage: Stage::SelectProject,
        selected_project: None,
        projects: load_projects(),
    }));

    // Outer box for border (GTK4 windows don't render borders properly)
    let outer_box = GtkBox::new(Orientation::Vertical, 0);
    outer_box.add_css_class("outer");

    let main_box = GtkBox::new(Orientation::Vertical, 10);
    main_box.set_margin_top(20);
    main_box.set_margin_bottom(20);
    main_box.set_margin_start(20);
    main_box.set_margin_end(20);

    build_project_list(&main_box, &state.borrow());
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

        // Cancel - hide instead of close
        if key == "q" || key == "escape" {
            window_clone.set_visible(false);
            // Reset state for next show
            let mut state = state_clone.borrow_mut();
            state.stage = Stage::SelectProject;
            state.selected_project = None;
            drop(state);
            build_project_list(&main_box_clone, &state_clone.borrow());
            return glib::Propagation::Stop;
        }

        let mut state = state_clone.borrow_mut();

        match state.stage {
            Stage::SelectProject => {
                if let Some(pos) = KEYS.iter().position(|&k| k.to_string() == key) {
                    if pos < state.projects.len() {
                        state.selected_project = Some(state.projects[pos].clone());
                        state.stage = Stage::SelectColumn;
                        drop(state);
                        build_column_select(&main_box_clone, &state_clone.borrow());
                    }
                }
            }
            Stage::SelectColumn => {
                let column = match key {
                    "h" => Some(2), // Claude
                    "j" => Some(3), // Nvim
                    _ => None,
                };
                if let Some(col) = column {
                    if let Some(ref project) = state.selected_project {
                        let project = project.clone();
                        // Reset state and hide
                        state.stage = Stage::SelectProject;
                        state.selected_project = None;
                        drop(state);
                        window_clone.set_visible(false);
                        build_project_list(&main_box_clone, &state_clone.borrow());
                        switch_to_project(&project, col);
                    }
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

    // Poll socket receiver
    let window_for_poll = window.clone();
    let state_for_poll = state.clone();
    let main_box_for_poll = main_box.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
        if let Ok(_cmd) = rx.try_recv() {
            let is_visible = window_for_poll.is_visible();
            if is_visible {
                // Hide and reset
                window_for_poll.set_visible(false);
                let mut state = state_for_poll.borrow_mut();
                state.stage = Stage::SelectProject;
                state.selected_project = None;
                drop(state);
                build_project_list(&main_box_for_poll, &state_for_poll.borrow());
            } else {
                // Refresh project list and show
                build_project_list(&main_box_for_poll, &state_for_poll.borrow());
                window_for_poll.set_visible(true);
                window_for_poll.present();
            }
        }
        glib::ControlFlow::Continue
    });
}

fn build_project_list(container: &GtkBox, state: &AppState) {
    // Clear
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }

    let header = Label::new(Some("Select project (q/Esc to cancel)"));
    header.add_css_class("header");
    container.append(&header);

    for (i, project) in state.projects.iter().enumerate() {
        if i >= KEYS.len() {
            break;
        }

        let row = GtkBox::new(Orientation::Horizontal, 10);

        let key_label = Label::new(Some(&format!("[{}]", KEYS[i])));
        key_label.add_css_class("key");
        row.append(&key_label);

        let exists = workspace_has_windows(&project.name);
        let name_text = if exists {
            project.name.clone()
        } else {
            format!("{} (new)", project.name)
        };
        let name_label = Label::new(Some(&name_text));
        name_label.add_css_class("project");
        row.append(&name_label);

        container.append(&row);
    }
}

fn build_column_select(container: &GtkBox, state: &AppState) {
    // Clear
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }

    if let Some(ref project) = state.selected_project {
        let header = Label::new(Some(&format!("Project: {}", project.name)));
        header.add_css_class("selected");
        container.append(&header);
    }

    let subheader = Label::new(Some("Select column (q/Esc to cancel)"));
    subheader.add_css_class("header");
    container.append(&subheader);

    let columns = [("h", "claude"), ("j", "nvim")];
    for (key, name) in columns {
        let row = GtkBox::new(Orientation::Horizontal, 10);

        let key_label = Label::new(Some(&format!("[{}]", key)));
        key_label.add_css_class("key");
        row.append(&key_label);

        let name_label = Label::new(Some(name));
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

    // Daemon mode: start GTK app with socket listener
    let (tx, rx) = mpsc::channel();
    start_socket_listener(tx);

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
