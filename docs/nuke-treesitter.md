# Nuke Treesitter Parsers

After a Homebrew nvim upgrade, treesitter parsers can get stale code signatures causing nvim to crash on boot with `SIGKILL (Code Signature Invalid)`.

## Fix

Remove all treesitter artifacts from `~/.local/share/nvim/site/` and caches:

```bash
rm -rf ~/.local/share/nvim/site/parser/
rm -rf ~/.local/share/nvim/site/parser-info/
rm -rf ~/.local/share/nvim/site/queries/
rm -rf ~/.local/share/nvim/lazy/nvim-treesitter/parser/
rm -rf ~/.cache/nvim/tree-sitter-*
rm -rf ~/.cache/nvim/luac/
```

Then open nvim normally. The `ensure_installed` list in `lua/plugins/treesitter.lua` will recompile the needed parsers.

## Why all three directories matter

- `parser/` — compiled `.so` files (the ones with broken signatures)
- `parser-info/` — metadata tracking which parsers are installed
- `queries/` — query files per language; if present, treesitter considers the parser "installed" and skips recompilation
