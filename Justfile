# Dotfiles task runner
# Run `just` to see all available recipes

mod nix
mod shell

# Default recipe - list all recipes
default:
    @just --list

# === Shortcuts ===

# Remove cached Neovim parsers after an upgrade
nuke-treesitter:
    bash scripts/nuke-treesitter.sh

# Interactive setup for a fresh Apple Silicon Mac
bootstrap-mac:
    bin/bootstrap-mac

# Switch nix configuration, or only Home Manager with --hm-only
switch mode="": (nix::switch mode)

# Switch only Home Manager
switch-hm: (nix::switch "--hm-only")

# First nix-darwin activation on the M1 Air, retaining Determinate Nix
bootstrap-darwin:
    bin/bootstrap-darwin

# Build the M1 configuration without activating it, on an Apple Silicon Mac
build-darwin: nix::build-darwin

# Sign this Mac into Tailscale and enable its SSH server
tailscale-login:
    sudo /run/current-system/sw/bin/tailscale up --ssh

# Compatibility aliases; remote-mode is also available directly on PATH
clamshell-on:
    remote-mode on

clamshell-off:
    remote-mode off

# Test keep-awake rules and sessions with fake hardware
test-keepawake:
    @just test-python tests/test_keepawake.py

# Format, typecheck, and exercise keep-awake rules with fake hardware
check-keepawake:
    uv run --locked ruff check --fix bin/keepawake tests/test_keepawake.py
    uv run --locked ruff format bin/keepawake tests/test_keepawake.py
    @just typecheck-python bin/keepawake tests/test_keepawake.py
    @just test-keepawake

# Test remote mode without changing the host's power settings
test-remote-mode:
    bash -n bin/remote-mode
    @just test-python tests/test_remote_mode.py

# Push the flake's cache-bundle (selected expensive builds) to Cachix
cache dry_run="": (nix::cache dry_run)

# Teach the system nix.conf about this flake's binary caches (needs sudo)
install-nix-caches: nix::install-nix-caches

# Update AI tool flake inputs and switch
ai: nix::ai

# Update all flake inputs with AI tool version report and switch
full-update: nix::full-update

# Install the locked Pi extension dependencies without lifecycle scripts
pi-install-deps:
    pnpm --dir config/pi install --frozen-lockfile --ignore-scripts

# Update selected Pi extension development dependencies without lifecycle scripts
pi-update-deps +packages:
    pnpm --dir config/pi update --ignore-scripts {{packages}}

# Require installed Pi, declared SDK pins, and installed SDKs to match
check-pi-version:
    uv run --locked python -B scripts/check-pi-version.py

# Check and typecheck Pi config/extensions
pi: pi-install-deps check-pi-version
    pnpm --dir config/pi run lint
    pnpm --dir config/pi run format
    pnpm --dir config/pi run typecheck
    pnpm --dir config/pi test

# Update all flake inputs and switch
update: nix::update

# Fetch private skills and refresh links on hosts that opt in through Home Manager
private-skills-sync:
    private-skills-sync

# Refresh private skill links without network access
private-skills-link:
    private-skills-sync --link-only

# === Formatters ===

# Format all
fmt: nix::fmt fmt-lua fmt-python

# Format Lua files
fmt-lua:
    stylua config/nvim config/hypr

# Format Python files
fmt-python:
    uv run --locked ruff check --fix && uv run --locked ruff format .

# === Linters ===

# Lint all
lint: nix::lint lint-lua lint-python

# Lint Lua files (TODO: fix selene config for neovim globals)
lint-lua:
    @true

# Lint Python files
lint-python:
    uv run --locked ruff check .

# === Type checking ===

# Install Blueprint's pinned runtime and development dependencies
blueprint-install:
    bun install --cwd bin/blueprint --frozen-lockfile --ignore-scripts

# Refresh Blueprint's lockfile after intentional dependency changes
blueprint-update:
    bun install --cwd bin/blueprint --ignore-scripts

# Format and typecheck the Bun renderer and directory server
check-blueprint: blueprint-install
    biome check --write bin/blueprint
    bun run bin/blueprint/node_modules/typescript/bin/tsc --project bin/blueprint/tsconfig.json

# Run a Bun development/verification script from the repository root
blueprint-run +args:
    bun run {{args}}

# Typecheck all
typecheck: typecheck-python

# Typecheck with the Nix-installed ty and uv-managed project/script environments
typecheck-python *files:
    TY_UV=scripts uv run --locked ty check {{files}}

# === Theme ===

# Validate the central theme and reject color-literal drift in consumers
check-theme:
    scripts/check-theme

# === Tests ===

# PR snapshot, wait, watch and thread commands against a fake gh
test-prctl:
    @just test-python tests/test_prctl.py

# Run all tests
test: test-keepawake test-display-recover test-fork-window test-spawn-session test-moto test-claude-mods test-nvim test-desktop-broker test-project-picker test-herdr-next-agent test-herdr-prune-workspaces test-nvim-here test-herdr-decorator test-direnv test-private-skills test-remote-mode test-prctl

# Session forking, exact session selection, and desktop routing
test-fork-window:
    @just test-python tests/test_fork_window.py

# Herdr session launcher repo lookup and agent naming
test-spawn-session:
    @just test-python tests/test_spawn_session.py

# Claude Code mods' own tests
test-claude-mods:
    @claude plugin test config/claude/mods/handoff

test-moto:
    @just test-python tests/test_moto.py
    @claude plugin test moto/claude/mods/moto-watch

# Validate private-skill behavior and the host opt-in list
check-private-skills: test-private-skills nix::check-private-skills

# Private skill cloning, offline updates, collision handling, and link cleanup
test-private-skills:
    @just test-python tests/test_private_skills.py

# Shared direnv helpers, independent of any Home Manager user.
test-direnv:
    bash -n nix/lib/direnv-stdlib.sh
    @just test-python tests/test_direnv_stdlib.py

# Project selection and backend dispatch
test-project-picker:
    bash -n bin/project-picker
    uv run --locked python -B -m pytest tests/test_project_picker.py

# Agent attention ranking and queue walking
test-herdr-next-agent:
    bash -n bin/herdr-next-agent
    uv run --locked python -B -m pytest tests/test_herdr_next_agent.py

# Finding the nearest Neovim and opening files in it, against headless Neovims
test-nvim-here:
    @just test-python tests/test_nvim_here.py

# PR and Jira sidebar decoration, the command palette, and the private work config
test-herdr-prune-workspaces:
    uv run --locked python -B -m pytest tests/test_herdr_prune_workspaces.py

test-herdr-decorator:
    uv run --locked python -B -m pytest tests/test_herdr_decorator.py tests/test_work_config.py tests/test_herdr_palette.py
    bash -n bin/pr-review bin/code-sync

# Run the sidebar decorator in the foreground, restarting it on every edit
herdr-decorator-dev:
    watchexec --restart --watch bin/herdr-decorator -- bin/herdr-decorator

# Run the moto job scheduler in the foreground, restarting it on every edit.
# Start it in a background-workspace tab, where it has Herdr's socket, and keep
# its cwd out of ~/code/<repo> so job workers open in their own workspaces.
moto-jobs-dev:
    watchexec --restart --watch bin/moto -- bin/moto job loop

# Run Python tests with the locked development dependencies
test-python *args:
    uv run --locked python -B -m pytest {{args}}

# Test display recovery, resume ordering, and closed-lid handling with fake tools
test-display-recover:
    bash -n bin/hypr-display-recover bin/hypr-panel-recover bin/wake-lg bin/dpms-on
    @just test-python tests/test_display_recover.py

# Check Hyprland scratchpad callbacks and terminal path quoting without a compositor
test-hypr-binds:
    bash -n bin/dpms-on bin/dpms-off
    nvim --headless -u NONE -l tests/test_hypr_binds.lua

# Check the desktop broker protocol and sandbox routing with a fake browser
test-desktop-broker:
    bash -n bin/open-url bin/sandbox bin/sandbox-wl-paste bin/sandbox-xdg-open
    @just test-python tests/test_desktop_broker.py tests/test_desktop_broker_clipboard.py

# Validate the active AeroSpace config on macOS without applying it
check-aerospace:
    aerospace reload-config --dry-run --warnings-as-errors --no-gui

# Run Neovim config tests
test-nvim:
    nix run ./nix#nvim -- --headless \
        +"lua local tests=require('tests'); assert(type(tests.run_all) == 'function'); tests.run_all()" \
        +qa

# === Combined workflows ===

# Format, lint, typecheck, evaluate current host, and check Pi extensions
check:
    nix develop ./nix --command just fmt check-parallel

[parallel]
check-parallel: check-blueprint test-keepawake test-display-recover lint typecheck pi test-fork-window test-spawn-session test-moto check-theme shell::check test-desktop-broker test-project-picker test-herdr-next-agent test-herdr-decorator test-direnv test-remote-mode test-prctl check-private-skills nix::eval

# Format, lint, and evaluate all hosts
check-all: fmt lint nix::eval-all

# CI: lint, typecheck, format, and test
ci: fmt lint typecheck check-theme check-blueprint test

# Build the Rosetta Linux builder for Apple Silicon
build-linux-builder:
    nix build ./nix#linux-builder --no-link --print-out-paths

# Force an x64 Linux derivation through the configured builder
check-linux-builder:
    #!/usr/bin/env bash
    set -euo pipefail
    result=$(nix build --impure --expr 'let pkgs = (builtins.getFlake (toString ./nix)).inputs.nixpkgs.legacyPackages.x86_64-linux; in pkgs.runCommand "linux-builder-smoke" { nonce = builtins.currentTime; } "uname -m > $out"' --max-jobs 0 --no-link --print-out-paths)
    cat "$result"
    test "$(cat "$result")" = x86_64
