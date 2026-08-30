# Neovim Notes

The immutable LazyVim package is assembled in `nix/lib/nvim-package.nix`; the Lua modules here are copied into its runtime path. Add LazyVim extras and external plugin source pins in Nix, while keeping plugin behavior in `lua/plugins/`.

Preferences:

- Leader key is `,` (comma).
- Clipboard is deliberately manual (`<space>y`/`<space>p`), not synced to the system clipboard.
- Colors come from the central theme (`nix/themes/monokai.json`), injected at build time via `vim.g.dotfiles_theme_path` and loaded by `lua/config/theme.lua` — no color literals in the Lua config. The editor background (`semantic.background`, `#222222`) is deliberately a shade lighter than Ghostty's `#1c1c1c`.
