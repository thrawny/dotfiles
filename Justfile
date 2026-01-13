# Dotfiles task runner - replaces mise.toml with pure Nix tooling

# Default recipe - show available commands
default:
    @just --list

# --- Nix workflows ---

# Switch configuration (auto-detects NixOS vs Home Manager)
switch:
    #!/usr/bin/env bash
    host=$(hostname | sed 's/\.local$//')
    if [ -f /etc/NIXOS ]; then
      echo "NixOS detected, running nixos-rebuild switch..."
      sudo nixos-rebuild switch --flake "./nix#$host"
    else
      echo "Standalone Home Manager detected, running home-manager switch..."
      home-manager switch --flake "./nix#$host"
    fi

# Dry-run NixOS rebuild (NixOS only)
dry:
    #!/usr/bin/env bash
    host=$(hostname)
    sudo nixos-rebuild dry-run --flake "./nix#$host"

# Build and show what changed (NixOS only)
diff:
    #!/usr/bin/env bash
    host=$(hostname)
    sudo nixos-rebuild build --flake "./nix#$host" && nvd diff /run/current-system result

# Clean up old Nix generations (keeps last 6) and optimize store
nix-clean:
    #!/usr/bin/env bash
    echo "==> Checking /nix/store size before cleanup..."
    du -sh /nix/store

    echo ""
    echo "==> Removing old user profile generations (keeping last 6)..."
    nix-env --delete-generations +6

    echo ""
    echo "==> Removing old system generations (keeping last 6)..."
    sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +6 || true

    echo ""
    echo "==> Running garbage collection..."
    nix-collect-garbage

    echo ""
    echo "==> Optimizing Nix store (deduplicating files)..."
    nix store optimise

    echo ""
    echo "==> Cleanup complete! Final /nix/store size:"
    du -sh /nix/store

# Evaluate Nix config without building (auto-detects NixOS vs Home Manager)
nix-eval:
    #!/usr/bin/env bash
    host=$(hostname | sed 's/\.local$//')
    if [ -f /etc/NIXOS ]; then
      echo "Evaluating NixOS config for $host..."
      nix eval "./nix#nixosConfigurations.$host.config.system.build.toplevel" --no-write-lock-file > /dev/null && echo "Config is valid"
    else
      echo "Evaluating Home Manager config for $host..."
      nix eval "./nix#homeConfigurations.$host.activationPackage" --no-write-lock-file > /dev/null && echo "Config is valid"
    fi

# --- Formatters ---

# Format Python sources with Ruff
fmt-python:
    uv run ruff check --fix && uv run ruff format .

# Format Neovim Lua config with Stylua
fmt-lua:
    stylua config/nvim

# Format Nix files with nixfmt via treefmt
fmt-nix:
    treefmt

# Run all formatters
fmt: fmt-python fmt-lua fmt-nix

alias f := fmt

# --- Linters ---

# Lint Python sources with Ruff
lint-python:
    uv run ruff check .

# Lint Neovim Lua config with Selene
lint-lua:
    selene config/nvim

# Lint Nix files with statix
lint-nix:
    statix check

# Run all linters
lint: lint-python lint-lua lint-nix

# --- Typechecking ---

# Typecheck Python code with basedpyright
typecheck-python:
    uv run basedpyright

# Run all type checks
typecheck: typecheck-python

# --- Tests ---

# Run Neovim config tests in headless mode
test-nvim:
    nvim --headless -u config/nvim/init.lua \
      +"lua local ok,tests=pcall(require,'tests'); if ok and tests.run_all then tests.run_all() end" \
      +qa

# Run all tests
test: test-nvim

# --- Aggregates ---

# Format, lint, and evaluate Nix config
nix-check: fmt-nix lint-nix nix-eval

# Run lint, typecheck, format, and tests (CI)
ci: fmt lint typecheck test
