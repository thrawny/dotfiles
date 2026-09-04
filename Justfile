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

# === Theme ===

# Validate the central theme and reject color-literal drift in consumers
check-theme:
    bin/check-theme

# === Tests ===

# Run all tests
test: test-nvim

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
