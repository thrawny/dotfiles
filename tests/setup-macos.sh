#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

test_home="$test_root/home"
mkdir -p "$test_home/dotfiles"
(
  cd "$source_root"
  tar --exclude=.git --exclude=.direnv --exclude=node_modules --exclude=.venv --exclude=result --exclude='.secrets*' -cf - .
) | tar -xf - -C "$test_home/dotfiles"

export HOME="$test_home"
export DOTFILES_SETUP_TESTING=1
setup="$HOME/dotfiles/bin/setup-macos"

"$setup" >/dev/null
[[ -L "$HOME/.zshrc" ]]
[[ $(readlink "$HOME/.zshrc") == "$HOME/dotfiles/portable/macos/home/zshrc" ]]
[[ -f "$HOME/dotfiles/config/claude/settings.json" ]]
[[ -f "$HOME/dotfiles/config/codex/config.toml" ]]
[[ -f "$HOME/dotfiles/config/pi/settings.json" ]]

# A second run converges without replacing correct links.
first_inode=$(stat -c %i "$HOME/.zshrc" 2>/dev/null || stat -f %i "$HOME/.zshrc")
"$setup" >/dev/null
second_inode=$(stat -c %i "$HOME/.zshrc" 2>/dev/null || stat -f %i "$HOME/.zshrc")
[[ "$first_inode" == "$second_inode" ]]

# Unmanaged conflicts are skipped unless --force is explicit.
rm "$HOME/.zshrc"
printf 'unmanaged\n' >"$HOME/.zshrc"
"$setup" >/dev/null
[[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]
"$setup" --force >/dev/null
[[ -L "$HOME/.zshrc" ]]
backup=$(printf '%s\n' "$HOME"/.dotfiles-backups/*/.zshrc)
[[ -f "$backup" ]]
[[ $(<"$backup") == unmanaged ]]

# A stale link into this repository is managed and repaired automatically.
rm "$HOME/.zshrc"
ln -s "$HOME/dotfiles/portable/macos/home/removed-zshrc" "$HOME/.zshrc"
"$setup" >/dev/null
[[ $(readlink "$HOME/.zshrc") == "$HOME/dotfiles/portable/macos/home/zshrc" ]]

"$setup" --dry-run >/dev/null
printf 'setup-macos test: ok\n'
