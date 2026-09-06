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

The container cannot test macOS casks, application discovery, or `defaults` changes. The VM test covers those on real macOS.

### Clean macOS VM test

Run these commands from the worktree root on an Apple Silicon Mac with macOS 14+, Python 3.9+, Git, and `just`:

```bash
just install-macos-vm-tools
just test-macos-vm --links-only
just test-macos-vm
just test-macos-vm --keep
```

The tool installer downloads and checksum-verifies Tart 2.34.0 into `~/.cache/dotfiles-tools/`. This version runs on Sequoia; the 2.35/2.36 release binaries have a [known missing Swift library issue on macOS 15](https://github.com/openai/tart/issues/1302). The runner uses the pinned binary directly. Override it with `TART_BIN=/path/to/tart` or `--tart /path/to/tart`.

The first run downloads a pinned Sequoia base image (23.6 GiB compressed, 50 GB virtual disk). Budget about 60–80 GiB free for the initial download and package installation. Subsequent runs reuse the cached image and APFS copy-on-write clones. The default guest has four CPUs and 6 GiB RAM; `--cpu` and `--memory` adjust these. The runner refuses to start below 30 GiB free in Tart storage; `--min-free-gib` changes that threshold. `TART_HOME` selects another storage location.

Each run copies the current tracked and non-ignored worktree into the guest's `~/dotfiles`, including uncommitted changes. Ignored files, live agent settings, secret paths, and caches are excluded. The host checkout is not mounted. The base image includes Homebrew. Full tests remove its npm-installed pnpm copy before installing the Brewfile’s pnpm. Installing Homebrew itself and interactive application behavior are outside this test. The Neovim smoke test checks startup and theme loading; headless exits can interrupt Mason language-tool installations, which can finish during an interactive editor session.

The runner stops and deletes its VM on completion, failure, or interruption. `--keep` retains a stopped VM and prints commands to inspect it. Logs and the filtered file manifest remain in the printed temporary directory. `guest.log` records each guest stage, `tart-run.log` records VM startup, and `run.json` records the image and tool versions. Use `--boot-timeout` and `--test-timeout` to change the bounded waits.

Run `just test-macos-vm-harness` to test snapshot filtering and VM cleanup without downloading or booting a VM. See [the testing plan](docs/tart-macos-testing-plan.md) for coverage and validation results.

## Nix usage

```bash
just switch   # Apply config (auto-detects NixOS vs Home Manager)
just check    # Format, lint, evaluate
```
