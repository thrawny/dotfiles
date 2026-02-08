use clap::{Parser, Subcommand};
use log::debug;
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

#[derive(Debug, Deserialize, Default, Clone, Copy, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Provider {
    Openai,
    #[default]
    Groq,
}

#[derive(Debug, Deserialize, Default)]
struct Config {
    #[serde(default)]
    provider: Provider,
    #[serde(default)]
    openai_api_key: String,
    #[serde(default)]
    groq_api_key: String,
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
        ("cloudmd", "CLAUDE.md"),
        ("claudemd", "CLAUDE.md"),
        ("weybar", "waybar"),
        ("vtype", "wtype"),
        ("jus", "just"),
        // Apps
        ("ghosty", "Ghostty"),
        ("sunbrowser", "Zen browser"),
        ("tail net", "tailnet"),
        ("urinal", "journal"),
        ("pmpm", "pnpm"),
        ("throni", "thrawny"),
        ("LTAB", "Alt Tab"),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v.to_string()))
    .collect()
}

fn load_config() -> Config {
    let path = config_path();
    let mut config = if let Ok(content) = std::fs::read_to_string(&path) {
        match toml::from_str(&content) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("Failed to parse {path:?}: {e}");
                Config::default()
            }
        }
    } else {
        Config::default()
    };

    // Allow env var to override provider
    if let Ok(provider) = std::env::var("VOICE_PROVIDER") {
        config.provider = match provider.to_lowercase().as_str() {
            "groq" => Provider::Groq,
            "openai" => Provider::Openai,
            _ => config.provider,
        };
    }

    if config.prompt.is_empty() {
        config.prompt = default_prompt();
    }

    // Merge user replacements on top of defaults
    let mut replacements = default_replacements();
    replacements.extend(config.replacements);
    config.replacements = replacements;

    debug!("provider={:?}", config.provider);
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
// Shared transcription and text processing
// ============================================================================

#[derive(Deserialize)]
struct TranscriptionResponse {
    text: String,
}

async fn transcribe_audio(
    audio_data: Vec<u8>,
    config: &Config,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let api_key = resolve_api_key(config)?;

    let file_part = reqwest::multipart::Part::bytes(audio_data)
        .file_name("audio.wav")
        .mime_str("audio/wav")?;

    let model = if config.model.is_empty() {
        default_model(config.provider)
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

    let endpoint = api_endpoint(config.provider);
    debug!("provider={:?} endpoint={endpoint}", config.provider);

    let client = reqwest::Client::new();
    let api_start = std::time::Instant::now();
    let response = client
        .post(endpoint)
        .bearer_auth(api_key)
        .multipart(form)
        .send()
        .await?;
    debug!("api_call: {:?}", api_start.elapsed());

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("API error {status}: {body}").into());
    }

    let result: TranscriptionResponse = response.json().await?;
    Ok(result.text.trim().to_string())
}

fn apply_replacements(text: &str, replacements: &HashMap<String, String>) -> String {
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
        let total_start = std::time::Instant::now();

        let stop_start = std::time::Instant::now();
        if let Some(mut child) = self.recorder.take() {
            let _ = child.kill().await;
            let _ = child.wait().await;
        }
        debug!("stop_recording: {:?}", stop_start.elapsed());

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
                debug!("audio bytes: {}", meta.len());
            }
        }

        self.state = State::Transcribing;
        notify("Transcribing...").await;

        let read_start = std::time::Instant::now();
        let audio_data = match tokio::fs::read(&self.audio_file).await {
            Ok(data) => data,
            Err(e) => {
                eprintln!("Failed to read audio file: {e}");
                notify(&format!("Error: {e}")).await;
                self.state = State::Idle;
                return;
            }
        };
        debug!("file_read: {:?}", read_start.elapsed());

        match transcribe_audio(audio_data, &self.config).await {
            Ok(text) => {
                debug!("raw: {text}");
                let text = apply_replacements(&text, &self.config.replacements);
                debug!("replaced: {text}");
                if !text.is_empty() {
                    let inject_start = std::time::Instant::now();
                    inject_text(&text).await;
                    debug!("inject: {:?}", inject_start.elapsed());
                }
            }
            Err(e) => {
                eprintln!("Transcription failed: {e}");
                notify(&format!("Error: {e}")).await;
            }
        }

        debug!("total: {:?}", total_start.elapsed());
        self.state = State::Idle;
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
    debug!(
        "wtype delay_ms={delay_ms} key_delay_ms={key_delay_ms} text_len={}",
        text.len()
    );

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
    debug!(
        "injector=clipboard delay_ms={delay_ms} text_len={}",
        text.len()
    );

    // Copy to regular clipboard (not primary) for universal compatibility
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

    // Use Ctrl+Shift+V to paste (works universally without conflicting with
    // Ghostty's Ctrl+V image paste or requiring xremap translation)
    let status = Command::new("wtype")
        .args([
            "-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl",
        ])
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
        .unwrap_or_else(|| "clipboard".to_string())
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
    let audio_data = match tokio::fs::metadata(&audio_file).await {
        Ok(meta) if meta.len() < 1000 => {
            eprintln!("No audio recorded (file too small)");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("No audio file created: {e}");
            std::process::exit(1);
        }
        Ok(meta) => {
            debug!("audio bytes: {}", meta.len());
            match tokio::fs::read(&audio_file).await {
                Ok(data) => data,
                Err(e) => {
                    eprintln!("Failed to read audio file: {e}");
                    std::process::exit(1);
                }
            }
        }
    };

    eprintln!("Transcribing...");

    // Transcribe
    let text = match transcribe_audio(audio_data, &config).await {
        Ok(text) => text,
        Err(e) => {
            eprintln!("Transcription failed: {e}");
            std::process::exit(1);
        }
    };

    // Apply replacements and print
    debug!("raw: {text}");
    let text = apply_replacements(&text, &config.replacements);
    debug!("replaced: {text}");
    println!("{text}");
}

fn resolve_api_key(config: &Config) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    match config.provider {
        Provider::Openai => {
            if !config.openai_api_key.is_empty() {
                return Ok(config.openai_api_key.clone());
            }
            std::env::var("OPENAI_API_KEY")
                .map_err(|_| "OPENAI_API_KEY not set and no openai_api_key in voice.toml".into())
        }
        Provider::Groq => {
            if !config.groq_api_key.is_empty() {
                return Ok(config.groq_api_key.clone());
            }
            std::env::var("GROQ_API_KEY")
                .map_err(|_| "GROQ_API_KEY not set and no groq_api_key in voice.toml".into())
        }
    }
}

fn api_endpoint(provider: Provider) -> &'static str {
    match provider {
        Provider::Openai => "https://api.openai.com/v1/audio/transcriptions",
        Provider::Groq => "https://api.groq.com/openai/v1/audio/transcriptions",
    }
}

fn default_model(provider: Provider) -> &'static str {
    match provider {
        Provider::Openai => "whisper-1",
        Provider::Groq => "whisper-large-v3-turbo",
    }
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main(flavor = "current_thread")]
async fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();
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
