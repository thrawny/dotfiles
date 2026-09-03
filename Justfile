# Dotfiles task runner
# Run `just` to see all available recipes

mod nix
mod nvim "config/nvim"

# Default recipe - list all recipes
default:
    @just --list

# === Shortcuts ===

# Switch nix configuration
switch: nix::switch

# Push the flake's cache-bundle (selected expensive builds) to Cachix
cache dry_run="": (nix::cache dry_run)

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
typecheck-python:
    basedpyright

# === Portable macOS ===

# Link portable macOS configuration (safe to rerun)
setup-macos *args:
    bin/setup-macos {{ args }}

# Install the portable macOS package set after Homebrew is available
install-macos-packages:
    bin/install-macos-packages

# Apply the opt-in macOS preference set
macos-defaults:
    bin/apply-macos-defaults

# Check portable macOS links, applications, and commands
check-macos:
    bin/check-macos

# Regenerate committed portable configuration from the canonical theme
generate-portable-theme:
    bin/generate-portable-theme

# === Theme ===

# Validate the central theme and reject color-literal drift in consumers
check-theme:
    bin/check-theme
    bin/generate-portable-theme --check

# === Tests ===

# Run all tests
test: test-nvim test-macos-portable

# Exercise portable macOS linking and conflict handling in a temporary home
test-macos-portable:
    tests/setup-macos.sh

# Build the Debian/Linuxbrew image and run the portable macOS E2E test
test-macos-container:
    tests/macos-container.sh

# Leave a playground container running from the previously built E2E image
macos-container-start:
    docker rm -f dotfiles-portable-macos-playground >/dev/null 2>&1 || true
    docker run -d --name dotfiles-portable-macos-playground --entrypoint sleep "${MACOS_CONTAINER_IMAGE:-dotfiles-portable-macos-test}" infinity
    @echo 'Enter with: just macos-container-shell'

# Open an interactive shell in the running playground container
macos-container-shell:
    docker exec -it dotfiles-portable-macos-playground zsh -l

# Stop the playground container
macos-container-stop:
    docker rm -f dotfiles-portable-macos-playground

# Run Neovim config tests
test-nvim:
    nix run ./nix#nvim -- --headless \
        +"lua local tests=require('tests'); assert(type(tests.run_all) == 'function'); tests.run_all()" \
        +qa

# === Combined workflows ===

# Format, lint, typecheck, evaluate current host, and check Pi extensions
check: fmt check-parallel

[parallel]
check-parallel: lint typecheck pi check-theme nix::eval

# Format, lint, and evaluate all hosts
check-all: fmt lint nix::eval-all

# CI: lint, typecheck, format, and test
ci: fmt lint typecheck check-theme test
