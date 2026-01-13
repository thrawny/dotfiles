#!/usr/bin/env bash

[[ "${TRACE}" ]] && set -x
set -eou pipefail
shopt -s nullglob

ensure_uv() {
  if ! command -v uv &>/dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

ensure_python() {
  # Install a managed Python if none is present
  if ! command -v python3 &>/dev/null; then
    local py="${DOTFILES_PYTHON_VERSION:-3.13}"
    echo "Installing managed Python ${py} with uv..."
    uv python install "${py}"
  fi
}

ensure_fnm() {
  # Install fnm (Fast Node Manager) if not present
  if ! command -v fnm &>/dev/null; then
    echo "Installing fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
    export PATH="$HOME/.local/share/fnm:$PATH"
  fi
}

ensure_node() {
  # Install Node via fnm if none is present
  export PATH="$HOME/.local/share/fnm:$PATH"
  if command -v fnm &>/dev/null; then
    eval "$(fnm env --shell bash)"
  fi
  if ! command -v node &>/dev/null; then
    local ver="${DOTFILES_NODE_VERSION:-24}"
    echo "Installing Node ${ver} with fnm..."
    fnm install "${ver}"
    fnm default "${ver}"
    eval "$(fnm env --shell bash)"
    corepack enable || true
  fi
}

setup_claude_code_cli() {
  # Install Claude Code CLI if Node is available
  if command -v node &>/dev/null; then
    echo "Installing @anthropic-ai/claude-code via npm..."
    npm install -g @anthropic-ai/claude-code || true
  else
    echo "Skipping Claude Code CLI install: node not found"
  fi

  # Prepare Claude config files from env if provided
  mkdir -p "$HOME/.claude"

  if [[ -n "${CLAUDE_CODE_CREDENTIALS:-}" ]] && [[ ! -s "$HOME/.claude/.credentials.json" ]]; then
    echo "Writing ~/.claude/.credentials.json from CLAUDE_CODE_CREDENTIALS"
    printf '%s' "$CLAUDE_CODE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
  fi
  if [[ -n "${CLAUDE_CODE_CONFIG:-}" ]] && [[ ! -s "$HOME/.claude.json" ]]; then
    echo "Writing ~/.claude.json from CLAUDE_CODE_CONFIG"
    printf '%s' "$CLAUDE_CODE_CONFIG" > "$HOME/.claude.json"
  fi

  # Adjust ownership of common mounts if present (best-effort)
  if command -v sudo &>/dev/null; then
    sudo chown -R "$USER":"$USER" "$HOME/.claude" 2>/dev/null || true
  fi
}

setup_codex_cli() {
  # Install Codex CLI via npm if Node is available
  if command -v node &>/dev/null; then
    echo "Installing @openai/codex via npm..."
    npm install -g @openai/codex || true
  else
    echo "Skipping Codex CLI install: node not found"
  fi

  # If CODEX_CREDENTIALS is provided (JSON matching auth.json), seed ~/.codex/auth.json
  # This mirrors CLAUDE_CODE_CREDENTIALS behavior for ChatGPT subscription-based auth.
  if [[ -n "${CODEX_CREDENTIALS:-}" ]]; then
    mkdir -p "$HOME/.codex" 2>/dev/null || true
    local codex_auth="${HOME}/.codex/auth.json"
    if [[ ! -s "${codex_auth}" ]]; then
      echo "Writing ~/.codex/auth.json from CODEX_CREDENTIALS"
      printf '%s' "$CODEX_CREDENTIALS" > "${codex_auth}"
      chmod 600 "${codex_auth}" 2>/dev/null || true
    fi
  fi

  # No additional config writes here; Ansible handles ~/.codex via ansible/all_config.yml
}

prime_zinit() {
  # Warm zinit and plugin caches so first SSH is fast
  if command -v zsh &>/dev/null; then
    echo "Priming zinit (installing manager + plugins)..."
    # Ensure ~/.zshrc is in place before this point (ansible has run)
    # Suppress devpod tmux auto-start and run interactive zsh to trigger zinit
    DEVPOD= ZDOTDIR="$HOME" zsh -i -c 'true' || true
    # Run an explicit update to fetch any turbo/deferred plugins in parallel
    DEVPOD= ZDOTDIR="$HOME" zsh -i -c 'zinit update --parallel || true' || true
  else
    echo "Skipping zinit priming: zsh not found"
  fi
}

main() {
  ensure_uv
  ensure_python
  ensure_fnm
  ensure_node

  # Backup conflicting dotfiles before linking
  if [ -f "$HOME/.zshrc" ]; then
    mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
  fi
  if [ -f "$HOME/.gitconfig" ]; then
    mv "$HOME/.gitconfig" "$HOME/.gitconfig.bak"
  fi

  echo "Setting up Python environment with uv..."
  uv sync

  # Install the package globally with its CLI entrypoints
  echo "Installing CLI commands globally..."
  uv tool install --editable .

  # Apply dotfile symlinks and other setup
  uv run ansible-playbook ansible/main.yml

  # Pre-download zinit and all declared plugins to avoid first-login fetch
  prime_zinit

  # Optional: install Claude Code CLI and setup config from env
  setup_claude_code_cli

  # Optional: install Codex CLI and wire env var for key
  setup_codex_cli

  echo "Configuring git..."
  if [ -n "${GIT_USER:-}" ]; then
    git config --global user.name "$GIT_USER"
    echo "Set git user.name to $GIT_USER"
  fi
  if [ -n "${GIT_EMAIL:-}" ]; then
    git config --global user.email "$GIT_EMAIL"
    echo "Set git user.email to $GIT_EMAIL"
  fi

  echo "Attempting to change default shell to zsh..."
  if command -v sudo &>/dev/null && sudo chsh -s "$(which zsh)" "$USER" 2>/dev/null; then
    echo "Successfully changed default shell to zsh"
  else
    echo "Info: Could not change default shell to zsh (sudo access may not be available)"
  fi

  if nvim --version &>/dev/null; then
    # Only run lazy.nvim tasks when nvim >= 0.8 to avoid Debian oldstable errors
    if nvim --headless '+lua print((vim.version().major*100+vim.version().minor) >= 8 and "ok" or "no")' +q 2>/dev/null | grep -q ok; then
      echo "Prepping nvim (lazy install)..."
      nvim --headless '+Lazy! install' +q || true
    else
      echo "Skipping nvim prep: Neovim < 0.8"
    fi
  fi

  if gh --version &>/dev/null; then
    gh auth setup-git || true
  fi
}

main "$@"
