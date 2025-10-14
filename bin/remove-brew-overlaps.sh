#!/usr/bin/env bash
set -euo pipefail

# Packages duplicated by Home Manager; safe to remove from Homebrew.
PACKAGES=(
  adoptopenjdk
  asdf
  autojump
  awscli
  bat
  coreutils
  cowsay
  curl
  direnv
  fzf
  gcloud-cli
  google-cloud-sdk
  gh
  git
  git-lfs
  go
  gnugrep
  gnused
  golangci-lint
  jq
  k9s
  kind
  lazygit
  neovim
  node
  pnpm
  postgresql@17
  python@3.13
  python@3.12
  python@3.11
  ripgrep
  ruff
  ruby
  starship
  tmux
  tree
  tree-sitter
  uv
  vim
  watch
  wget
  yq
  zsh
)

log() {
  printf '%s\n' "$1"
}

uninstall() {
  local pkg="$1"
  if ! brew list --formula "$pkg" >/dev/null 2>&1; then
    log "skip: $pkg not installed via Homebrew"
    return
  fi

  log "removing: $pkg"
  brew uninstall --ignore-dependencies "$pkg"
}

main() {
  if ! command -v brew >/dev/null 2>&1; then
    log "error: brew not found"
    exit 1
  fi

  for pkg in "${PACKAGES[@]}"; do
    uninstall "$pkg"
  done

  log "done"
}

main "$@"
