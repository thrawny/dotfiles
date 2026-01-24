use clap::{Parser, Subcommand};
use serde::Deserialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::process::{Child, Command};
use tokio::sync::Mutex;

// ============================================================================
// Config
// ============================================================================

#[derive(Debug, Deserialize, Default)]
struct Config {
    #[serde(default)]
    prompt: String,
    #[serde(default)]
    language: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    replacements: HashMap<String, String>,
}

fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("voice.toml")
}

fn default_prompt() -> String {
    "I'm working on the NixOS configuration with Home Manager. \
     Let me check the Neovim setup in LazyVim. \
     Claude Code suggested refactoring the TypeScript and Rust code. \
     The Hyprland keybindings need updating, same with the Niri config. \
     I'll use tmux and Ghostty for the terminal session. \
     The Kubernetes deployment needs the PostgreSQL migration to run first. \
     Let me check the GitHub pull request and run the CI workflow."
        .to_string()
}

fn default_replacements() -> HashMap<String, String> {
    [
        // Wayland compositors
        ("hyperland", "Hyprland"),
        ("hyper land", "Hyprland"),
        ("neary", "Niri"),
        // Editors
        ("neovim", "Neovim"),
        ("neo vim", "Neovim"),
        ("lazy vim", "LazyVim"),
        ("lazyvim", "LazyVim"),
        // Nix
        ("nix os", "NixOS"),
        ("home manager", "Home Manager"),
        // Claude
        ("cloude code", "Claude Code"),
        ("cloud code", "Claude Code"),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v.to_string()))
    .collect()
}

fn load_config() -> Config {
    let path = config_path();
    let mut config = if let Ok(content) = std::fs::read_to_string(&path) {
        toml::from_str(&content).unwrap_or_default()
    } else {
        Config::default()
    };

    if config.prompt.is_empty() {
        config.prompt = default_prompt();
    }

    // Merge user replacements on top of defaults
    let mut replacements = default_replacements();
    replacements.extend(config.replacements);
    config.replacements = replacements;

    config
}

// ============================================================================
// State
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq)]
enum State {
    Idle,
    Recording,
    Transcribing,
}

impl State {
    fn as_str(&self) -> &'static str {
        match self {
            State::Idle => "idle",
            State::Recording => "recording",
            State::Transcribing => "transcribing",
        }
    }
}

// ============================================================================
// Daemon
// ============================================================================

struct Daemon {
    state: State,
    config: Config,
    recorder: Option<Child>,
    audio_file: PathBuf,
}

impl Daemon {
    fn new() -> Self {
        let audio_file = std::env::temp_dir().join("voice-recording.wav");
        Self {
            state: State::Idle,
            config: load_config(),
            recorder: None,
            audio_file,
        }
    }

    async fn toggle(&mut self) -> &'static str {
        match self.state {
            State::Idle => {
                self.start_recording().await;
                "recording"
            }
            State::Recording => {
                self.stop_and_transcribe().await;
                "transcribing"
            }
            State::Transcribing => "busy",
        }
    }

    async fn cancel(&mut self) -> &'static str {
        if let Some(mut child) = self.recorder.take() {
            let _ = child.kill().await;
        }
        self.state = State::Idle;
        notify("Cancelled").await;
        "cancelled"
    }

    async fn start_recording(&mut self) {
        let _ = tokio::fs::remove_file(&self.audio_file).await;

        let child = Command::new("pw-record")
            .args([
                "--format",
                "s16",
                "--rate",
                "16000",
                "--channels",
                "1",
                self.audio_file.to_str().unwrap(),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();

        match child {
            Ok(child) => {
                self.recorder = Some(child);
                self.state = State::Recording;
                notify("Recording...").await;
            }
            Err(e) => {
                eprintln!("Failed to start pw-record: {e}");
                notify("Failed to start recording").await;
            }
        }
    }

    async fn stop_and_transcribe(&mut self) {
        if let Some(mut child) = self.recorder.take() {
            let _ = child.kill().await;
            let _ = child.wait().await;
        }

        // Check if we got any audio
        match tokio::fs::metadata(&self.audio_file).await {
            Ok(meta) if meta.len() < 1000 => {
                eprintln!("No audio recorded");
                notify("No audio recorded").await;
                self.state = State::Idle;
                return;
            }
            Err(_) => {
                eprintln!("No audio file");
                notify("Recording failed").await;
                self.state = State::Idle;
                return;
            }
            Ok(meta) => {
                debug_log(&format!("DEBUG audio bytes: {}", meta.len()));
            }
        }

        self.state = State::Transcribing;
        notify("Transcribing...").await;

        match self.transcribe().await {
            Ok(text) => {
                debug_log(&format!("DEBUG raw: {text}"));
                let text = self.apply_replacements(&text);
                debug_log(&format!("DEBUG replaced: {text}"));
                if !text.is_empty() {
                    inject_text(&text).await;
                }
            }
            Err(e) => {
                eprintln!("Transcription failed: {e}");
                notify(&format!("Error: {e}")).await;
            }
        }

        self.state = State::Idle;
    }

    async fn transcribe(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let api_key = std::env::var("OPENAI_API_KEY")?;
        let audio_data = tokio::fs::read(&self.audio_file).await?;

        let file_part = reqwest::multipart::Part::bytes(audio_data)
            .file_name("audio.wav")
            .mime_str("audio/wav")?;

        let model = if self.config.model.is_empty() {
            "whisper-1"
        } else {
            &self.config.model
        };

        let mut form = reqwest::multipart::Form::new()
            .part("file", file_part)
            .text("model", model.to_string());

        if !self.config.language.is_empty() {
            form = form.text("language", self.config.language.clone());
        }

        if !self.config.prompt.is_empty() {
            form = form.text("prompt", self.config.prompt.clone());
        }

        let client = reqwest::Client::new();
        let response = client
            .post("https://api.openai.com/v1/audio/transcriptions")
            .bearer_auth(api_key)
            .multipart(form)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(format!("API error {status}: {body}").into());
        }

        #[derive(Deserialize)]
        struct TranscriptionResponse {
            text: String,
        }

        let result: TranscriptionResponse = response.json().await?;
        Ok(result.text.trim().to_string())
    }

    fn apply_replacements(&self, text: &str) -> String {
        let mut result = text.to_string();
        for (from, to) in &self.config.replacements {
            // Case-insensitive replacement
            let mut i = 0;
            while let Some(pos) = result[i..].to_lowercase().find(&from.to_lowercase()) {
                let abs_pos = i + pos;
                result.replace_range(abs_pos..abs_pos + from.len(), to);
                i = abs_pos + to.len();
            }
        }
        result
    }
}

// ============================================================================
// Text injection & notifications
// ============================================================================

async fn inject_text(text: &str) {
    let mode = injection_mode();
    if mode == "clipboard" {
        inject_via_clipboard(text).await;
        return;
    }

    let delay_ms = wtype_delay_ms(&mode);
    let key_delay_ms = wtype_key_delay_ms();
    debug_log(&format!(
        "DEBUG wtype delay_ms={delay_ms} key_delay_ms={key_delay_ms} text_len={}",
        text.len()
    ));

    let mut cmd = Command::new("wtype");
    if delay_ms > 0 {
        cmd.args(["-s", &delay_ms.to_string()]);
    }
    if key_delay_ms > 0 {
        cmd.args(["-d", &key_delay_ms.to_string()]);
    }
    cmd.arg("--").arg(text);
    let status = cmd.status().await;
    if let Err(e) = status {
        eprintln!("wtype failed: {e}");
        notify("Injection failed").await;
    }
}

async fn inject_via_clipboard(text: &str) {
    let delay_ms = wtype_delay_ms("clipboard");
    debug_log(&format!(
        "DEBUG injector=clipboard delay_ms={delay_ms} text_len={}",
        text.len()
    ));

    let mut copy = Command::new("wl-copy");
    copy.arg("--").arg(text);
    if let Err(e) = copy.status().await {
        eprintln!("wl-copy failed: {e}");
        notify("Injection failed").await;
        return;
    }

    if delay_ms > 0 {
        tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
    }

    let paste_mod = paste_modifier();
    let paste_key = paste_key();
    let status = Command::new("wtype")
        .args(["-M", &paste_mod, "-k", &paste_key, "-m", &paste_mod])
        .status()
        .await;

    if let Err(e) = status {
        eprintln!("wtype failed: {e}");
        notify("Injection failed").await;
    }
}

async fn notify(message: &str) {
    let _ = Command::new("notify-send")
        .args(["--app-name=voice", "--expire-time=2000", "Voice", message])
        .status()
        .await;
}

fn wtype_delay_ms(mode: &str) -> u64 {
    std::env::var("VOICE_WTYPE_DELAY_MS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or_else(|| if mode == "clipboard" { 50 } else { 100 })
}

fn wtype_key_delay_ms() -> u64 {
    std::env::var("VOICE_WTYPE_KEY_DELAY_MS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(5)
}

fn injection_mode() -> String {
    std::env::var("VOICE_INJECT_MODE")
        .ok()
        .unwrap_or_else(|| "direct".to_string())
}

fn paste_modifier() -> String {
    std::env::var("VOICE_PASTE_MOD")
        .ok()
        .unwrap_or_else(|| "logo".to_string())
}

fn paste_key() -> String {
    std::env::var("VOICE_PASTE_KEY")
        .ok()
        .unwrap_or_else(|| "v".to_string())
}

// ============================================================================
// Socket server
// ============================================================================

fn socket_path() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("voice.sock")
}

async fn run_server(daemon: Arc<Mutex<Daemon>>) -> Result<(), Box<dyn std::error::Error>> {
    let path = socket_path();
    let _ = tokio::fs::remove_file(&path).await;

    let listener = UnixListener::bind(&path)?;
    println!("Listening on {path:?}");

    loop {
        let (stream, _) = listener.accept().await?;
        let daemon = daemon.clone();
        tokio::spawn(handle_client(stream, daemon));
    }
}

async fn handle_client(stream: UnixStream, daemon: Arc<Mutex<Daemon>>) {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    if reader.read_line(&mut line).await.is_ok() {
        let response = match line.trim() {
            "toggle" => {
                let mut d = daemon.lock().await;
                d.toggle().await.to_string()
            }
            "cancel" => {
                let mut d = daemon.lock().await;
                d.cancel().await.to_string()
            }
            "status" => {
                let d = daemon.lock().await;
                d.state.as_str().to_string()
            }
            _ => "unknown".to_string(),
        };

        let _ = writer.write_all(response.as_bytes()).await;
        let _ = writer.write_all(b"\n").await;
    }
}

async fn send_command(cmd: &str) -> Result<String, Box<dyn std::error::Error>> {
    let path = socket_path();
    let mut stream = UnixStream::connect(&path).await?;

    stream.write_all(cmd.as_bytes()).await?;
    stream.write_all(b"\n").await?;

    let mut reader = BufReader::new(stream);
    let mut response = String::new();
    reader.read_line(&mut response).await?;

    Ok(response.trim().to_string())
}

// ============================================================================
// CLI
// ============================================================================

#[derive(Parser)]
#[command(name = "voice", about = "Voice-to-text for Wayland")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the daemon
    Serve,
    /// Toggle recording on/off
    Toggle,
    /// Cancel current operation
    Cancel,
    /// Get current status
    Status,
    /// One-shot: record until Enter, transcribe, print to stdout
    Once,
}

// ============================================================================
// One-shot mode
// ============================================================================

async fn run_once() {
    let config = load_config();
    let audio_file = std::env::temp_dir().join("voice-recording.wav");
    let _ = tokio::fs::remove_file(&audio_file).await;

    // Start recording
    let mut child = match Command::new("pw-record")
        .args([
            "--format",
            "s16",
            "--rate",
            "16000",
            "--channels",
            "1",
            audio_file.to_str().unwrap(),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(e) => {
            eprintln!("Failed to start pw-record: {e}");
            std::process::exit(1);
        }
    };

    eprintln!("Recording... (press Enter to stop)");

    // Wait for Enter or Ctrl+C
    let mut line = String::new();
    let _ = std::io::stdin().read_line(&mut line);

    // Stop recording
    let _ = child.kill().await;
    let _ = child.wait().await;

    // Check if we got any audio
    match tokio::fs::metadata(&audio_file).await {
        Ok(meta) if meta.len() < 1000 => {
            eprintln!("No audio recorded (file too small)");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("No audio file created: {e}");
            std::process::exit(1);
        }
        Ok(meta) => {
            debug_log(&format!("DEBUG audio bytes: {}", meta.len()));
        }
    }

    eprintln!("Transcribing...");

    // Transcribe
    let text = match transcribe_file(&audio_file, &config).await {
        Ok(text) => text,
        Err(e) => {
            eprintln!("Transcription failed: {e}");
            std::process::exit(1);
        }
    };

    // Apply replacements and print
    debug_log(&format!("DEBUG raw: {text}"));
    let text = apply_replacements_static(&text, &config.replacements);
    debug_log(&format!("DEBUG replaced: {text}"));
    println!("{text}");
}

async fn transcribe_file(
    audio_file: &PathBuf,
    config: &Config,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let api_key = std::env::var("OPENAI_API_KEY")?;
    let audio_data = tokio::fs::read(audio_file).await?;

    let file_part = reqwest::multipart::Part::bytes(audio_data)
        .file_name("audio.wav")
        .mime_str("audio/wav")?;

    let model = if config.model.is_empty() {
        "whisper-1"
    } else {
        &config.model
    };

    let mut form = reqwest::multipart::Form::new()
        .part("file", file_part)
        .text("model", model.to_string());

    if !config.language.is_empty() {
        form = form.text("language", config.language.clone());
    }

    if !config.prompt.is_empty() {
        form = form.text("prompt", config.prompt.clone());
    }

    let client = reqwest::Client::new();
    let response = client
        .post("https://api.openai.com/v1/audio/transcriptions")
        .bearer_auth(api_key)
        .multipart(form)
        .send()
        .await?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("API error {status}: {body}").into());
    }

    #[derive(Deserialize)]
    struct TranscriptionResponse {
        text: String,
    }

    let result: TranscriptionResponse = response.json().await?;
    Ok(result.text.trim().to_string())
}

fn apply_replacements_static(text: &str, replacements: &HashMap<String, String>) -> String {
    let mut result = text.to_string();
    for (from, to) in replacements {
        let mut i = 0;
        while let Some(pos) = result[i..].to_lowercase().find(&from.to_lowercase()) {
            let abs_pos = i + pos;
            result.replace_range(abs_pos..abs_pos + from.len(), to);
            i = abs_pos + to.len();
        }
    }
    result
}

fn debug_log(message: &str) {
    if std::env::var("VOICE_DEBUG").ok().as_deref() != Some("1") {
        return;
    }
    println!("{message}");
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Serve => {
            let daemon = Arc::new(Mutex::new(Daemon::new()));

            let daemon_for_signal = daemon.clone();
            tokio::spawn(async move {
                let _ = tokio::signal::ctrl_c().await;
                let mut d = daemon_for_signal.lock().await;
                let _ = d.cancel().await;
                std::process::exit(0);
            });

            if let Err(e) = run_server(daemon).await {
                eprintln!("Server error: {e}");
                std::process::exit(1);
            }
        }
        Commands::Toggle => match send_command("toggle").await {
            Ok(response) => println!("{response}"),
            Err(e) => {
                eprintln!("Failed to connect: {e} (is daemon running?)");
                std::process::exit(1);
            }
        },
        Commands::Cancel => match send_command("cancel").await {
            Ok(response) => println!("{response}"),
            Err(e) => {
                eprintln!("Failed to connect: {e}");
                std::process::exit(1);
            }
        },
        Commands::Status => match send_command("status").await {
            Ok(response) => println!("{response}"),
            Err(e) => {
                eprintln!("Failed to connect: {e}");
                std::process::exit(1);
            }
        },
        Commands::Once => {
            run_once().await;
        }
    }
}
