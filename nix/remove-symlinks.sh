#!/usr/bin/env bash
# Remove symlinks that will be managed by home-manager
# Errors out if any file is not a symlink

set -e

FILES=(
  "$HOME/.zshrc"
  "$HOME/.tmux.conf"
  "$HOME/.gitconfig"
  "$HOME/.gitconfig.local"
  "$HOME/.gitignoreglobal"
  "$HOME/.npmrc"
  "$HOME/.config/nvim"
  "$HOME/.config/ghostty"
  "$HOME/.config/starship.toml"
  "$HOME/.config/k9s"
  "$HOME/.codex"
  "$HOME/Library/Application Support/lazygit"
)

echo "Checking files before removal..."
for file in "${FILES[@]}"; do
  if [[ -e "$file" ]] && [[ ! -L "$file" ]]; then
    echo "ERROR: $file exists but is NOT a symlink. Aborting."
    exit 1
  fi
done

echo "All existing files are symlinks. Removing..."
for file in "${FILES[@]}"; do
  if [[ -L "$file" ]]; then
    echo "Removing: $file -> $(readlink "$file")"
    rm "$file"
  else
    echo "Skipping (doesn't exist): $file"
  fi
done

echo "Done! Ready for home-manager switch."
