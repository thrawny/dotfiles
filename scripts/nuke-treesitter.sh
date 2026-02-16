#!/usr/bin/env bash
# Nuke treesitter parsers to fix SIGKILL (Code Signature Invalid) crashes
# after a Homebrew/Nix nvim upgrade on macOS.
# Nvim will recompile parsers from ensure_installed on next launch.
set -euo pipefail

dirs=(
  ~/.local/share/nvim/site/parser
  ~/.local/share/nvim/site/parser-info
  ~/.local/share/nvim/site/queries
  ~/.local/share/nvim/lazy/nvim-treesitter/parser
  ~/.cache/nvim/luac
)

removed=0
for dir in "${dirs[@]}"; do
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    echo "removed $dir"
    ((removed++))
  fi
done

# Glob for tree-sitter cache files separately (may not exist)
for f in ~/.cache/nvim/tree-sitter-*; do
  if [[ -e "$f" ]]; then
    rm -rf "$f"
    echo "removed $f"
    ((removed++))
  fi
done

if ((removed == 0)); then
  echo "nothing to clean"
else
  echo "cleaned $removed items — open nvim to recompile parsers"
fi
