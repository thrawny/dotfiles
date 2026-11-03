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

# Prepare app-only fleet candidates without changing installed services or pins.
prepare-nightly-app-update:
    uv run --locked python scripts/nightly-app-update.py --prepare --state-dir "$HOME/.local/state/nightly-app-update"

# Exercise validation with the system PATH launchd gives the updater.
check-nightly-app-update-environment:
    env PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin {{just_executable()}} check

# Install only the updater schedule; leave active app services and HM untouched.
install-nightly-app-update:
    #!/usr/bin/env bash
    set -euo pipefail
    updater_plist=$(nix build --no-link --print-out-paths ./nix#homeConfigurations.thrawnym1.config.dotfiles.nightlyAppUpdate.plist)
    uv run --locked python scripts/install-nightly-app-update.py "$updater_plist"

nightly-app-update-status:
    uv run --locked python scripts/nightly-app-update.py --verify --state-dir "$HOME/.local/state/nightly-app-update"
    launchctl print "gui/$(id -u)/org.nix-community.home.nightly-app-update"

nightly-app-update-pause:
    mkdir -p "$HOME/.local/state/nightly-app-update"
    touch "$HOME/.local/state/nightly-app-update/paused"

nightly-app-update-resume:
    rm -f "$HOME/.local/state/nightly-app-update/paused"

# Apply T3 model defaults and shortcuts live, without restarting its server
sync-t3code-preferences target="thrawny-z13":
    bash scripts/sync-t3code-preferences {{quote(target)}}

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
lint: nix::lint lint-python

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

# Typecheck Python, optionally selecting files, with the locked environments
typecheck *files:
    TY_UV=scripts uv run --locked ty check {{files}}

# === Theme ===

# Validate the central theme and reject color-literal drift in consumers
check-theme:
    scripts/check-theme

# === Tests ===

# Run Python, Neovim, and Claude mod tests
test: test-python test-nvim test-claude-mods

# Claude Code mods' own tests
test-claude-mods:
    @claude plugin test config/claude/mods/handoff
    @claude plugin test moto/claude/mods/moto-watch

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
    #!/usr/bin/env bash
    set -euo pipefail
    # Check tools also need small local builds on hosts with max-jobs = 0.
    export NIX_CONFIG="$(printf '%s\n' "${NIX_CONFIG:-}" 'max-jobs = 1' 'cores = 2')"
    nix develop ./nix --command just fmt check-parallel

[parallel]
check-parallel: lint typecheck pi check-blueprint test check-theme shell::check nix::eval

# Format, lint, and evaluate all hosts
check-all: fmt lint nix::eval-all

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
