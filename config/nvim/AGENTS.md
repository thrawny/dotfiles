# Neovim Notes

The immutable LazyVim package is assembled in `nix/lib/nvim-package.nix`; the Lua modules here are copied into its runtime path. Add LazyVim extras and external plugin source pins in Nix, while keeping plugin behavior in `lua/plugins/`.

After Lua edits run `just test-nvim` from the repo root. The change reaches the editor after `just switch`; `nix run ./nix#nvim` launches the pending build without switching. To test a local CodeDiff checkout, `nix build ./nix#nvim --override-input nvim-codediff path:/abs/path`.

Preferences:

- Leader key is `,` (comma).
- Clipboard is deliberately manual (`<space>y`/`<space>p`), not synced to the system clipboard.
- Colors come from the central theme (`nix/themes/monokai.json`), injected at build time via `vim.g.dotfiles_theme_path` and loaded by `lua/config/theme.lua` — no color literals in the Lua config. The editor background (`semantic.background`, `#222222`) is deliberately a shade lighter than Ghostty's `#1c1c1c`.
