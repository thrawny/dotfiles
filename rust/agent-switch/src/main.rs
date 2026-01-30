mod daemon;
mod state;
mod tmux;
mod track;

#[cfg(feature = "niri")]
mod niri;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "agent-switch",
    about = "Track and switch between AI agent sessions"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Handle hook events from agents (reads JSON from stdin)
    Track {
        /// Event type: session-start, session-end, prompt-submit, stop, notification
        event: String,
    },
    /// Re-associate focused window with orphan session
    Fix,
    /// List all sessions as JSON
    List,
    /// Remove stale sessions
    Cleanup,
    /// Tmux picker (daemonless)
    Tmux {
        /// Skip keyboard UI, go straight to fzf search
        #[arg(long)]
        fzf: bool,
    },
    /// Run the daemon (session cache + file watchers)
    Serve {
        /// Enable niri GTK overlay (Linux only)
        #[cfg(feature = "niri")]
        #[arg(long)]
        niri: bool,
    },
    /// Niri GTK daemon (deprecated, use `serve --niri`)
    #[cfg(feature = "niri")]
    Niri {
        /// Toggle visibility (send to running daemon)
        #[arg(long)]
        toggle: bool,
    },
}

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    let cli = Cli::parse();

    match cli.command {
        Command::Track { event } => {
            if !track::handle_event(&event) {
                std::process::exit(1);
            }
        }
        Command::Fix => todo!("fix command"),
        Command::List => {
            let mut store = state::load();
            state::cleanup_stale(&mut store);
            state::save(&store);
            if let Ok(json) = serde_json::to_string_pretty(&store) {
                println!("{}", json);
            }
        }
        Command::Cleanup => {
            let mut store = state::load();
            state::cleanup_stale(&mut store);
            state::save(&store);
        }
        Command::Tmux { fzf } => {
            if fzf {
                tmux::run_fzf_only();
            } else {
                tmux::run();
            }
        }
        #[cfg(feature = "niri")]
        Command::Serve { niri } => {
            if niri {
                let exit_code = niri::run_with_daemon();
                std::process::exit(exit_code.into());
            } else {
                daemon::run_headless();
            }
        }
        #[cfg(not(feature = "niri"))]
        Command::Serve {} => {
            daemon::run_headless();
        }
        #[cfg(feature = "niri")]
        Command::Niri { toggle } => {
            let exit_code = niri::run(toggle);
            std::process::exit(exit_code.into());
        }
    }
}
