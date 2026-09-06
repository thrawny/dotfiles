#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d)
# macOS exposes /var through /private/var; setup uses physical paths.
test_root=$(cd "$test_root" && pwd -P)
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
[[ -L "$HOME/.zshrc" ]] || exit 1
[[ $(readlink "$HOME/.zshrc") == "$HOME/dotfiles/portable/macos/home/zshrc" ]] || exit 1
[[ $(readlink "$HOME/.config/herdr/config.toml") == "$HOME/dotfiles/portable/macos/generated/herdr.toml" ]] || exit 1
[[ -f "$HOME/dotfiles/config/claude/settings.json" ]] || exit 1
[[ -f "$HOME/dotfiles/config/codex/config.toml" ]] || exit 1
[[ -f "$HOME/dotfiles/config/pi/settings.json" ]] || exit 1
for skill_source in "$HOME/dotfiles"/portable/macos/generated/agent-skills/.agents/skills/*; do
  [[ -d "$skill_source" && -f "$skill_source/SKILL.md" ]] || continue
  skill_name=$(basename "$skill_source")
  [[ $(readlink "$HOME/.claude/skills/$skill_name") == "$skill_source" ]] || exit 1
  [[ $(readlink "$HOME/.codex/skills/$skill_name") == "$skill_source" ]] || exit 1
  [[ $(readlink "$HOME/.pi/agent/skills/$skill_name") == "$skill_source" ]] || exit 1
done

# A second run converges without replacing correct links.
first_inode=$(stat -c %i "$HOME/.zshrc" 2>/dev/null || stat -f %i "$HOME/.zshrc")
"$setup" >/dev/null
second_inode=$(stat -c %i "$HOME/.zshrc" 2>/dev/null || stat -f %i "$HOME/.zshrc")
[[ "$first_inode" == "$second_inode" ]] || exit 1

# Unmanaged conflicts are skipped unless --force is explicit.
rm "$HOME/.zshrc"
printf 'unmanaged\n' >"$HOME/.zshrc"
"$setup" >/dev/null
[[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]] || exit 1
"$setup" --force >/dev/null
[[ -L "$HOME/.zshrc" ]] || exit 1
backup=$(printf '%s\n' "$HOME"/.dotfiles-backups/*/.zshrc)
[[ -f "$backup" ]] || exit 1
[[ $(<"$backup") == unmanaged ]] || exit 1

# A stale link into this repository is managed and repaired automatically.
rm "$HOME/.zshrc"
ln -s "$HOME/dotfiles/portable/macos/home/removed-zshrc" "$HOME/.zshrc"
"$setup" >/dev/null
[[ $(readlink "$HOME/.zshrc") == "$HOME/dotfiles/portable/macos/home/zshrc" ]] || exit 1

"$setup" --dry-run >/dev/null
printf 'setup-macos test: ok\n'
