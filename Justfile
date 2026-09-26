# Dotfiles task runner
# Run `just` to see all available recipes

mod nix
mod shell
mod nvim "config/nvim"

# Default recipe - list all recipes
default:
    @just --list

# === Shortcuts ===

# Interactive setup for a fresh Apple Silicon Mac
bootstrap-mac:
    bin/bootstrap-mac

# Switch nix configuration, or only Home Manager with --hm-only
switch mode="": (nix::switch mode)

# First nix-darwin activation on the M1 Air, retaining Determinate Nix
bootstrap-darwin:
    bin/bootstrap-darwin

# Build the M1 configuration without activating it, on an Apple Silicon Mac
build-darwin: nix::build-darwin

# Sign this Mac into Tailscale and enable its SSH server
tailscale-login:
    sudo /run/current-system/sw/bin/tailscale up --ssh

# Keep this Mac awake with the lid closed; persists until clamshell-off
clamshell-on:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "$(uname -s)" = Darwin ]] || { echo "macOS required" >&2; exit 1; }
    /usr/bin/pmset -g batt | grep -q "AC Power" || { echo "Connect AC power first" >&2; exit 1; }
    sudo /usr/bin/pmset -a disablesleep 1
    echo "Sleep disabled, including on battery. Run just clamshell-off before unplugging or packing the Mac."
    /usr/bin/pmset -g

# Restore lid-close/manual sleep; AC idle sleep stays disabled by nix-darwin
clamshell-off:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "$(uname -s)" = Darwin ]] || { echo "macOS required" >&2; exit 1; }
    sudo /usr/bin/pmset -a disablesleep 0
    /usr/bin/pmset -g

# Push the flake's cache-bundle (selected expensive builds) to Cachix
cache dry_run="": (nix::cache dry_run)

# Teach the system nix.conf about this flake's binary caches (needs sudo)
install-nix-caches: nix::install-nix-caches

# Update AI tool flake inputs and switch
ai: nix::ai

# Update all flake inputs with AI tool version report and switch
full-update: nix::full-update

# Check and typecheck Pi config/extensions
pi:
    pnpm --dir config/pi run lint
    pnpm --dir config/pi run format
    pnpm --dir config/pi run typecheck
    pnpm --dir config/pi test

# Update all flake inputs and switch
update: nix::update

# === Formatters ===

# Format all
fmt: nix::fmt fmt-lua fmt-python

# Format Lua files
fmt-lua:
    stylua config/nvim config/hypr

# Format Python files
fmt-python:
    ruff check --fix && ruff format .

# === Linters ===

# Lint all
lint: nix::lint lint-lua lint-python

# Lint Lua files (TODO: fix selene config for neovim globals)
lint-lua:
    @true

# Lint Python files
lint-python:
    ruff check .

# === Type checking ===

# Typecheck all
typecheck: typecheck-python

# Typecheck Python code
typecheck-python *files:
    uv run --locked basedpyright {{files}}

# === Theme ===

# Validate the central theme and reject color-literal drift in consumers
check-theme:
    scripts/check-theme

# === Tests ===

# Format and check the T3 Code CLI
check-t3ctl:
    ruff check --fix bin/t3ctl tests/test_t3ctl.py
    ruff format bin/t3ctl tests/test_t3ctl.py
    @just typecheck-python bin/t3ctl tests/test_t3ctl.py
    @just test-t3ctl

# Test T3 Code API commands and credential cleanup without a live server
test-t3ctl:
    @just test-python tests/test_t3ctl.py

# Run all tests
test: test-nvim test-aerospace test-niri-layout test-desktop-broker test-project-picker test-herdr-next-agent test-herdr-decorator test-bootstrap-mac test-t3ctl test-direnv

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

# PR and Jira sidebar decoration, the command palette, and the private work config
test-herdr-decorator:
    uv run --locked python -B -m pytest tests/test_herdr_decorator.py tests/test_work_config.py tests/test_herdr_palette.py
    bash -n bin/pr-review bin/code-sync

# Run the sidebar decorator in the foreground, restarting it on every edit
herdr-decorator-dev:
    watchexec --restart --watch bin/herdr-decorator -- bin/herdr-decorator

# Run Python tests with the locked development dependencies
test-python *args:
    uv run --locked python -B -m pytest {{args}}

# Check AeroSpace keybindings, app rules, and terminal launcher shell syntax
# Portable checks only; macOS behavior still needs a smoke test.
test-aerospace:
    @just test-python tests/test_aerospace.py

# Check niri layout detection with mocked desktop commands
test-niri-layout:
    bash -n bin/niri-layout
    @just test-python tests/test_niri_layout.py

# Check the desktop broker protocol and sandbox routing with a fake browser
test-desktop-broker:
    bash -n bin/niri-open-url bin/sandbox bin/sandbox-wl-paste bin/sandbox-xdg-open
    @just test-python tests/test_desktop_broker.py tests/test_desktop_broker_clipboard.py

# Validate the active AeroSpace config on macOS without applying it
check-aerospace:
    aerospace reload-config --dry-run --warnings-as-errors --no-gui

# Test the Mac bootstrap walkthrough without changing this machine
test-bootstrap-mac:
    python3 tests/test_bootstrap_mac.py

# Run Neovim config tests
test-nvim:
    nix run ./nix#nvim -- --headless \
        +"lua local tests=require('tests'); assert(type(tests.run_all) == 'function'); tests.run_all()" \
        +qa

# === Combined workflows ===

# Format, lint, typecheck, evaluate current host, and check Pi extensions
check: fmt check-parallel

[parallel]
check-parallel: lint typecheck pi check-theme shell::check test-aerospace test-niri-layout test-desktop-broker test-project-picker test-herdr-next-agent test-herdr-decorator test-t3ctl test-direnv nix::eval

# Format, lint, and evaluate all hosts
check-all: fmt lint nix::eval-all

# CI: lint, typecheck, format, and test
ci: fmt lint typecheck check-theme test
