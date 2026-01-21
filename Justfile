# Dotfiles task runner
# Run `just` to see all available recipes

# Default recipe - list all recipes
default:
    @just --list

# === Shortcuts ===

# Switch nix configuration (alias for nix::switch)
switch: (nix::switch)

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

# Lint Lua files
lint-lua:
    selene config/nvim

# Lint Python files
lint-python:
    uv run ruff check .

# Lint Rust files
lint-rust:
    just rust::clippy

# === Type checking ===

# Typecheck all
typecheck: typecheck-python

# Typecheck Python code
typecheck-python:
    uv run basedpyright

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

# === Submodules ===

mod nix
mod rust
