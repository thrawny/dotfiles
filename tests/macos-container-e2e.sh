#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_SETUP_TESTING=1
repo_root="$HOME/dotfiles"
cd "$repo_root"

bin/setup-macos
[[ -L "$HOME/.zshrc" ]]
[[ -L "$HOME/.aerospace.toml" ]]
[[ -L "$HOME/.config/ghostty/config" ]]
[[ -L "$HOME/.config/herdr/config.toml" ]]
[[ -L "$HOME/.config/nvim" ]]
[[ -f config/claude/settings.json ]]
[[ -f config/codex/config.toml ]]
[[ -f config/pi/settings.json ]]

bin/install-macos-packages

# Reapplying the public setup command must preserve correct links.
zsh_link_before=$(readlink "$HOME/.zshrc")
bin/setup-macos
[[ $(readlink "$HOME/.zshrc") == "$zsh_link_before" ]]

# An unmanaged file survives by default and is backed up under --force.
rm "$HOME/.zshrc"
printf 'unmanaged\n' >"$HOME/.zshrc"
bin/setup-macos
[[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]
bin/setup-macos --force
[[ -L "$HOME/.zshrc" ]]
backup=$(printf '%s\n' "$HOME"/.dotfiles-backups/*/.zshrc)
[[ $(<"$backup") == unmanaged ]]

bin/generate-portable-theme --check
git config --file "$HOME/.gitconfig" --get delta.syntax-theme | grep -Fx 'Monokai Extended'
jq -e . "$HOME/.pi/agent/settings.json" "$HOME/.pi/agent/themes/monokai-pi.json" >/dev/null
yq eval '.' "$HOME/.config/lazygit/config.yml" >/dev/null
python3 - <<'PY'
import tomllib
from pathlib import Path

for config_path in (
    Path.home() / ".aerospace.toml",
    Path.home() / ".config/herdr/config.toml",
    Path.home() / ".config/hunk/config.toml",
    Path.home() / ".config/starship.toml",
):
    with config_path.open("rb") as config_file:
        tomllib.load(config_file)
PY
zsh -lic 'brew --version >/dev/null && command -v herdr starship direnv fzf zoxide >/dev/null'
herdr config check
hunk --version
btop --version
k9s version
yazi --version
yq eval '.' "$HOME/.config/k9s/config.yaml" "$HOME/.config/k9s/aliases.yaml" \
  "$HOME/.config/k9s/views.yaml" "$HOME/.config/k9s/skins/monokai.yaml" >/dev/null
zsh -lic '[[ "$XDG_CONFIG_HOME" == "$HOME/.config" ]] && typeset -f y >/dev/null'
git config --file "$HOME/.gitconfig" --get pager.diff | grep -Fx 'hunk pager'


tmux -L portable-e2e -f "$HOME/.config/tmux/tmux.conf" new-session -d 'sleep 10'
[[ $(tmux -L portable-e2e show-options -gv prefix) == C-a ]]
tmux -L portable-e2e kill-server

nvim --headless "+lua assert(vim.g.colors_name == 'monokai-pro')" +qa
bin/check-macos

# Keep the playground image small without removing installed tools.
rm -rf "$HOME/.cache/Homebrew" "$HOME/.npm/_cacache"
pnpm store prune

printf 'portable macOS container E2E: ok\n'
