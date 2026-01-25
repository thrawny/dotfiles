use crate::state;
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::fs::OpenOptions;
use std::io::{self, Read, Write};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

const KEYS: [char; 12] = ['h', 'j', 'k', 'l', 'u', 'i', 'o', 'p', 'n', 'm', ',', '.'];

#[derive(Clone)]
struct TmuxWindow {
    session_name: String,
    session_index: String, // e.g. "main:1"
    window_id: String,     // e.g. "@5"
    window_name: String,
}

#[derive(Clone, Copy)]
enum AgentState {
    Waiting,
    Responding,
    Idle,
}

impl AgentState {
    fn from_str(state: &str) -> Option<Self> {
        match state {
            "waiting" => Some(Self::Waiting),
            "responding" => Some(Self::Responding),
            "idle" => Some(Self::Idle),
            _ => None,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Responding => "working",
            Self::Idle => "idle",
        }
    }

    fn color(self) -> &'static str {
        match self {
            Self::Waiting => "\x1b[1;33m",  // bold yellow
            Self::Responding => "\x1b[34m", // blue
            Self::Idle => "\x1b[90m",       // gray
        }
    }
}

#[allow(dead_code)]
enum ScreenState {
    Sessions,
    Windows {
        target_session: String,
        session_windows: Vec<TmuxWindow>,
    },
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
    file: fs::File,
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

fn key_to_index(key: char) -> i32 {
    KEYS.iter()
        .position(|&k| k == key)
        .map(|v| v as i32)
        .unwrap_or(-1)
}

fn list_tmux_windows() -> Vec<TmuxWindow> {
    let output = Command::new("tmux")
        .args([
            "list-windows",
            "-a",
            "-F",
            "#{session_name}:#{window_index}\t#{window_id}\t#{window_name}",
        ])
        .output()
        .ok();

    let output = match output {
        Some(o) if o.status.success() => o,
        _ => return Vec::new(),
    };

    let mut windows = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 3 {
            continue;
        }
        let session_name = parts[0].split(':').next().unwrap_or("").to_string();
        // Skip dev and scratch sessions
        if session_name == "dev" || session_name == "scratch" {
            continue;
        }
        windows.push(TmuxWindow {
            session_name,
            session_index: parts[0].to_string(),
            window_id: parts[1].to_string(),
            window_name: parts[2].to_string(),
        });
    }
    windows
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

    items
}

fn sorted_sessions(windows: &[TmuxWindow], order: &[String]) -> Vec<String> {
    let mut sessions = Vec::new();
    let mut seen = HashSet::new();
    for window in windows {
        if seen.insert(window.session_name.clone()) {
            sessions.push(window.session_name.clone());
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

fn format_status(state: AgentState) -> String {
    format!("{}[{}]\x1b[0m", state.color(), state.label())
}

fn status_for_window(
    window: &TmuxWindow,
    status_by_tmux_id: &HashMap<String, &state::Session>,
) -> Option<String> {
    status_by_tmux_id
        .get(&window.window_id)
        .and_then(|s| AgentState::from_str(&s.state))
        .map(format_status)
}

fn terminal_lines() -> usize {
    if env::var("TMUX").is_ok()
        && let Ok(output) = Command::new("tmux")
            .args(["display-message", "-p", "#{pane_height}"])
            .output()
        && output.status.success()
        && let Ok(value) = String::from_utf8(output.stdout)
        && let Ok(lines) = value.trim().parse::<usize>()
    {
        return lines;
    }

    if let Ok(output) = Command::new("tput").arg("lines").output()
        && output.status.success()
        && let Ok(value) = String::from_utf8(output.stdout)
    {
        return value.trim().parse::<usize>().unwrap_or(24);
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

fn render_sessions_screen(
    tty: &mut Option<Tty>,
    sessions: &[String],
    windows: &[TmuxWindow],
    status_by_tmux_id: &HashMap<String, &state::Session>,
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
        for (widx, window) in windows
            .iter()
            .filter(|w| &w.session_name == session)
            .enumerate()
        {
            if line_count >= max_lines {
                break;
            }
            let wkey = if widx < KEYS.len() { KEYS[widx] } else { '?' };
            let status = status_for_window(window, status_by_tmux_id);
            let line = if let Some(status) = status {
                format!("{} {} {}", window.session_index, status, window.window_name)
            } else {
                format!("{} {}", window.session_index, window.window_name)
            };
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
    windows: &[TmuxWindow],
    status_by_tmux_id: &HashMap<String, &state::Session>,
) -> Vec<TmuxWindow> {
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
    for (widx, window) in windows
        .iter()
        .filter(|w| w.session_name == target_session)
        .enumerate()
    {
        session_windows.push(window.clone());
        let wkey = if widx < KEYS.len() { KEYS[widx] } else { '?' };
        let status = status_for_window(window, status_by_tmux_id);
        let line = if let Some(status) = status {
            format!("{} {} {}", window.session_index, status, window.window_name)
        } else {
            format!("{} {}", window.session_index, window.window_name)
        };
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

fn run_fzf_search(windows: &[TmuxWindow]) {
    let mut input = String::new();
    for window in windows {
        input.push_str(&format!(
            "{}\t{} {}\n",
            window.session_index, window.session_index, window.window_name
        ));
    }

    let mut fzf = match Command::new("fzf")
        .args([
            "--ansi",
            "--no-border",
            "--height=100%",
            "--with-nth=2..",
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
    let target = selected.split('\t').next().unwrap_or("").trim();
    if target.is_empty() {
        return;
    }

    let _ = Command::new("tmux")
        .args(["switch-client", "-t", target])
        .status();
}

pub fn run() {
    if env::var("TMUX").is_err() {
        eprintln!("agent-switch tmux must run inside tmux");
        return;
    }

    let mut store = state::load();
    state::cleanup_stale(&mut store);
    state::save(&store);

    let windows = list_tmux_windows();
    if windows.is_empty() {
        eprintln!("No tmux windows found");
        return;
    }

    let session_order = load_session_order();
    let sessions = sorted_sessions(&windows, &session_order);

    // Build lookup by tmux_id for agent status
    let status_by_tmux_id: HashMap<String, &state::Session> = store
        .sessions
        .values()
        .filter_map(|s| s.window.tmux_id.as_ref().map(|id| (id.clone(), s)))
        .collect();

    let mut tty_out = Tty::open();

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
        loop {
            let key = if let Some(tty) = tty_in.as_mut() {
                tty.read_key()
            } else {
                let mut buf = [0u8; 1];
                if io::stdin().read_exact(&mut buf).is_ok() {
                    Some(buf[0] as char)
                } else {
                    None
                }
            };
            match key {
                Some(k) => {
                    if key_tx.send(k).is_err() {
                        break;
                    }
                }
                None => break,
            }
        }
    });

    let mut screen = ScreenState::Sessions;
    render_sessions_screen(&mut tty_out, &sessions, &windows, &status_by_tmux_id);

    loop {
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
                        let err = Command::new(exe).arg("tmux").arg("--fzf").exec();
                        eprintln!("Failed to exec fzf mode: {err}");
                    }
                    run_fzf_search(&windows);
                    return;
                }

                if key == 'q' || key == 27 as char {
                    return;
                }

                let session_idx = key_to_index(key);
                if session_idx < 0 || session_idx as usize >= sessions.len() {
                    return;
                }

                let target_session = sessions[session_idx as usize].clone();
                let session_windows = render_windows_screen(
                    &mut tty_out,
                    &target_session,
                    &windows,
                    &status_by_tmux_id,
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
                    return;
                }

                let window_idx = window_idx as usize;
                let target = session_windows
                    .get(window_idx)
                    .map(|w| w.session_index.clone())
                    .unwrap_or_default();
                if target.is_empty() {
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

pub fn run_fzf_only() {
    if env::var("TMUX").is_err() {
        eprintln!("agent-switch tmux must run inside tmux");
        return;
    }

    let windows = list_tmux_windows();
    if windows.is_empty() {
        eprintln!("No tmux windows found");
        return;
    }

    run_fzf_search(&windows);
}
