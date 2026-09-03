# Dotfiles

Personal dotfiles with both the existing Nix configuration and an additive, non-Nix setup for Apple Silicon Macs.

## Stack

| Layer    | Tool                      |
| -------- | ------------------------- |
| Config   | Nix/Home Manager or portable shell scripts |
| WM       | Niri on Linux, AeroSpace on macOS          |
| Terminal | Ghostty                   |
| Editor   | Neovim (LazyVim)          |
| Shell    | Zsh + Starship            |

## Structure

```
nix/      # NixOS & Home Manager modules
config/   # Tool configs linked or seeded by Nix
bin/      # Scripts and utilities added to PATH
skills/   # Local agent skills linked into Claude, Pi, and Codex
```

## Portable macOS setup

The supported checkout location is `~/dotfiles`. Applying configuration requires only the macOS system tools and is safe to repeat:

```bash
git clone --branch without-nix https://github.com/thrawny/dotfiles.git ~/dotfiles
~/dotfiles/bin/setup-macos
```

The setup script links portable configuration, seeds missing local Claude, Codex, and Pi settings from their examples, and leaves unmanaged conflicts alone. Review the report, then use `--force` to back up and replace those conflicts:

```bash
~/dotfiles/bin/setup-macos --force
```

Homebrew is optional during setup. Once it is installed or approved, install the base terminal, editor, agent, and AeroSpace packages:

```bash
~/dotfiles/bin/install-macos-packages
~/dotfiles/bin/check-macos
```

macOS preference changes are separate and opt-in:

```bash
~/dotfiles/bin/apply-macos-defaults
```

The portable files under `portable/macos/generated/` are committed so initial setup does not need generators or network access. After changing `nix/themes/monokai.json`, regenerate the themed files with `just generate-portable-theme`.

External agent skills are also committed there, including their `skills-lock.json`. Their selected sources live in `portable/macos/skills.sources.tsv`. Refresh the exact set from upstream, review the generated diff, and commit it:

```bash
just update-portable-skills
just test-macos-portable
```

`bin/setup-macos` links both the generated external skills and the repo-owned `skills/` into Claude, Codex, and Pi.

A Debian container exercises the setup as a non-root user, installs the formula portion of the Brewfile through Linuxbrew, starts the configured shell, tmux, and Neovim, and checks repeat runs and conflict backups:

```bash
just test-macos-container
just macos-container-start
just macos-container-shell
# later: just macos-container-stop
```

The container cannot test macOS casks, application launch, or `defaults` changes. Those remain covered by `bin/check-macos` on a real Mac.

## Nix usage

```bash
just switch   # Apply config (auto-detects NixOS vs Home Manager)
just check    # Format, lint, evaluate
```
