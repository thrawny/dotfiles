# Set up a new Mac

Use this guide to install the `without-nix` branch directly on a new Apple Silicon Mac. Keep the checkout at `~/dotfiles`, because the configuration links point there. Nix and Tart are not needed.

## Interactive walkthrough

Open Apple's Terminal app and run:

```bash
bootstrap_file=$(mktemp -t dotfiles-bootstrap)
curl -fsSL https://raw.githubusercontent.com/thrawny/dotfiles/without-nix/bin/bootstrap-macos -o "$bootstrap_file" && /bin/bash "$bootstrap_file"
rm -f "$bootstrap_file"
```

This downloads the script before running it, so it can read your answers from the terminal. Git, Homebrew, and `just` do not need to be installed beforehand. The script offers to install developer tools and Homebrew, clones the `without-nix` branch into `~/dotfiles` if needed, then walks through the steps below.

Press Enter to choose the displayed default, answer `n` to skip an offered step, or use `q` or Ctrl-C to stop. Package installation waits until Homebrew and configuration links are ready. Replacing existing configuration requires a separate choice and creates backups. Sign-ins, app launches, and macOS preferences are optional and default to no.

To rerun after the checkout exists:

```bash
/bin/bash "$HOME/dotfiles/bin/bootstrap-macos"
```

The script detects existing tools and preserves checkout edits. It does not pull updates or switch an existing checkout's branch. Review and pull updates yourself before rerunning when needed. Failed commands stop the walkthrough with the current step name. Deferred work is listed at the end, and failed verification returns a nonzero exit status.

You can also run `just bootstrap-macos` from `~/dotfiles` after packages are installed. The sections below are the manual equivalent and explain what each step changes.

The package and configuration setup passed on macOS Sequoia 15.7.7 in a clean VM. That image already had Homebrew. The interactive script's decision paths are tested with isolated homes and mocked installers using `just test-macos-bootstrap`. An actual fresh Homebrew installation through the walkthrough has not been tested.

## 1. Prepare Terminal and Git

Open Apple's Terminal app. Run each section in order, waiting for installations to finish before continuing.

```bash
uname -m
xcode-select -p
```

`uname -m` must print `arm64`. If it prints `x86_64` on an Apple Silicon Mac, reopen Terminal without Rosetta. Intel Macs are not supported by these dotfiles scripts.

If `xcode-select -p` reports that developer tools are missing, run this and complete the installer window:

```bash
xcode-select --install
```

Then confirm Git works:

```bash
git --version
```

## 2. Make Homebrew available

First check the standard Apple Silicon location. This also handles an existing installation that is missing from your shell's PATH:

```bash
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew
```

If Homebrew is missing, install it using the command from the [Homebrew homepage](https://brew.sh/):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Complete its prompts, then run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Whether Homebrew was already installed or you just installed it, check:

```bash
brew --version
brew --prefix
brew update
```

The prefix should be `/opt/homebrew`. A `/usr/local` installation is usually the Intel version and does not match this setup. Homebrew currently supports macOS 14 and newer and requires Xcode Command Line Tools or Xcode. See its [installation requirements](https://docs.brew.sh/Installation).

On a managed Mac, use your company's Homebrew installation process if required. You can do step 3 without Homebrew and return to step 4 once it is available. The dotfiles installer does not install Homebrew itself.

## 3. Clone and link the configuration

```bash
git clone --branch without-nix https://github.com/thrawny/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
bin/setup-macos --dry-run
bin/setup-macos
```

If `~/dotfiles` already exists, inspect that checkout before continuing. Do not clone over it or delete it to make the command succeed. These instructions expect the `without-nix` branch.

Setup creates symlinks and copies missing local agent settings from the committed examples. It leaves existing unmanaged files alone and prints `skip unmanaged conflict` for each one. Homebrew may have created a `.zprofile`, so a conflict there is normal.

After reviewing the report, back up and replace the conflicts:

```bash
bin/setup-macos --force
```

Backups go under `~/.dotfiles-backups/<timestamp>-<pid>/`, preserving each file's path. Repeating setup leaves correct links and existing live settings in place. Keep `~/dotfiles` where it is after installation.

These bootstrap commands use `bin/` directly because `just` is not installed yet. Later task commands run from the repository root.

## 4. Install packages and plugins

Make the new command locations available in this Terminal session, then install:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="$HOME/dotfiles/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.local/share/pnpm:$PATH"
bin/install-macos-packages
```

Run this as your normal user. The script installs the [Brewfile](../Brewfile), trusts the AeroSpace and zmx taps, and installs Pi, acpx, shell and tmux plugins, Neovim plugins, Pi dependencies, and the browser used by agent-browser. Downloads and any installer prompts need to finish before continuing.

If installation stops, read the error, fix its cause, and rerun the same command. It can also update existing packages and plugins.

Open Ghostty from Applications, or run:

```bash
open -a Ghostty
```

Use its new terminal window for the remaining commands so the linked login shell configuration is loaded.

## 5. Add your identity and sign in

Replace the example name and email before running:

```bash
git config --file "$HOME/.gitconfig.local" user.name "Your Name"
git config --file "$HOME/.gitconfig.local" user.email "you@example.com"
gh auth login
```

Choose GitHub.com and HTTPS to match the clone URL. The shared Git configuration already uses `gh` for GitHub credentials. Keep personal identity in `~/.gitconfig.local`, since `~/.gitconfig` is a symlink to the shared configuration.

Launch `claude`, `codex`, and `pi` individually and complete the sign-in or provider setup for the tools you use. Credentials are not copied by this repository. Setup seeds these gitignored files for your machine-specific changes:

- `~/dotfiles/config/claude/settings.json`
- `~/dotfiles/config/codex/config.toml`
- `~/dotfiles/config/pi/settings.json`

Local shell additions belong in `~/.zsh.local`.

## 6. Open the desktop apps and check the setup

Open AeroSpace from Applications. Complete its Accessibility permission prompt to let it manage windows. The supplied configuration enables start at login. Open Neovim with `nvim` and leave it open while any remaining Mason language tools finish installing.

In Ghostty:

```bash
cd "$HOME/dotfiles"
just check-macos
brew bundle check --file Brewfile
```

Aim for `0 problem(s)`. Missing optional `agent-history` and `agent-switch` commands are warnings and do not block setup. A missing Git identity file is also a warning, resolved in step 5. The checks verify commands, app discovery, and configuration links; they do not verify account authentication or macOS permissions.

The repository's `.envrc` still loads the Nix development environment. Leave it blocked by direnv on this non-Nix setup. You can run these `just` recipes without `direnv allow`.

## 7. Apply macOS preferences if wanted

This step is optional. Read [the preference script](../bin/apply-macos-defaults) first. It changes Finder, Dock, keyboard repeat, screenshots, clock format, and update preferences. It also disables the empty-Trash warning.

```bash
cd "$HOME/dotfiles"
just macos-defaults
```

When convenient, restart Finder and Dock to pick up the changes:

```bash
killall Finder Dock
```

## Update later

From `~/dotfiles`, review or commit any local edits, then:

```bash
git pull --ff-only
just setup-macos
just install-macos-packages
just check-macos
```

Review any new conflicts before using `just setup-macos --force`. Generated theme files and external skills are committed, so a normal setup or update does not need to regenerate them.

To try a change in a disposable VM first, follow [the VM instructions in the README](../README.md#clean-macos-vm-test).
