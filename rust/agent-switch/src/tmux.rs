use crate::state;
use std::io::Write;
use std::process::{Command, Stdio};

struct TmuxRow {
    tmux_id: String,
    line: String,
}

#[derive(Clone, Copy)]
enum AgentState {
    Waiting,
    Responding,
    Idle,
    Unknown,
}

impl AgentState {
    fn from_str(state: &str) -> Self {
        match state {
            "waiting" => Self::Waiting,
            "responding" => Self::Responding,
            "idle" => Self::Idle,
            _ => Self::Unknown,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Responding => "working",
            Self::Idle => "idle",
            Self::Unknown => "?",
        }
    }

    fn color(self) -> &'static str {
        match self {
            Self::Waiting => "\x1b[31m",
            Self::Responding => "\x1b[32m",
            Self::Idle => "\x1b[90m",
            Self::Unknown => "\x1b[90m",
        }
    }
}

pub fn run() {
    let mut store = state::load();
    state::cleanup_stale(&mut store);
    state::save(&store);

    let mut rows: Vec<TmuxRow> = store
        .sessions
        .values()
        .filter_map(|session| {
            let tmux_id = session.window.tmux_id.clone()?;
            let state = AgentState::from_str(&session.state);
            let cwd = session.cwd.clone().unwrap_or_else(|| "?".to_string());
            let line = format!(
                "{}[{}]\x1b[0m {}: {}",
                state.color(),
                state.label(),
                session.agent,
                cwd
            );
            Some(TmuxRow { tmux_id, line })
        })
        .collect();

    if rows.is_empty() {
        return;
    }

    rows.sort_by(|a, b| a.line.cmp(&b.line));

    let mut input = String::new();
    for row in &rows {
        input.push_str(&row.tmux_id);
        input.push('\t');
        input.push_str(&row.line);
        input.push('\n');
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
        .args(["select-window", "-t", target])
        .status();
}
