# Dotfiles task runner
# Run `just` to see all available recipes

headless := if env("DISPLAY", "") != "" { "false" } else if env("WAYLAND_DISPLAY", "") != "" { "false" } else if os() == "macos" { "false" } else { "true" }

# Default recipe - list all recipes
default:
    @just --list

# === Shortcuts ===

# Switch nix configuration and install Rust binaries (skip rust on headless)
switch:
    just nix::switch
    {{ if headless != "true" { "just rust::install" } else { "" } }}

# Update AI tool flake inputs and switch
ai:
    just nix::ai

# === Formatters ===

# Format all
fmt: (nix::fmt) fmt-lua fmt-python fmt-rust

# Format Lua files
fmt-lua:
    stylua config/nvim

# Format Python files
fmt-python:
    uv run ruff check --fix && uv run ruff format .

# Format Rust files
fmt-rust:
    just rust::fmt

# === Linters ===

# Lint all
lint: (nix::lint) lint-lua lint-python lint-rust

# Lint Lua files (TODO: fix selene config for neovim globals)
lint-lua:
    @true

# Lint Python files
lint-python:
    uv run ruff check .

# Lint Rust files
lint-rust:
    just rust::clippy

# === Type checking ===

# Typecheck all
typecheck: typecheck-python typecheck-pi-extensions

# Typecheck Python code
typecheck-python:
    uv run basedpyright

# Typecheck Pi TypeScript extensions
# Uses latest TypeScript from config/pi/extensions/package.json
typecheck-pi-extensions:
    pnpm --dir config/pi/extensions install
    pnpm --dir config/pi/extensions run typecheck

# === Tests ===

# Run all tests
test: test-nvim

# Run Neovim config tests
test-nvim:
    nvim --headless -u config/nvim/init.lua \
        +"lua local ok,tests=pcall(require,'tests'); if ok and tests.run_all then tests.run_all() end" \
        +qa

# === Combined workflows ===

# Format, lint, and evaluate current host
check: fmt lint (nix::eval)

# Format, lint, and evaluate all hosts
check-all: fmt lint (nix::eval-all)

# CI: lint, typecheck, format, and test
ci: fmt lint typecheck test

# === Setup ===

# Configure git hooks for this repo
setup-hooks:
    git config core.hooksPath scripts
    chmod +x scripts/pre-commit
    @echo "Configured core.hooksPath to scripts/"

# === Submodules ===

mod nix
mod rust
mod nvim "config/nvim"
