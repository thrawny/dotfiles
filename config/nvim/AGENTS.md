# Neovim Notes

The immutable LazyVim package is assembled in `nix/lib/nvim-package.nix`; the Lua modules here are copied into its runtime path. Add LazyVim extras and external plugin source pins in Nix, while keeping plugin behavior in `lua/plugins/`.

Preferences:

- Leader key is `,` (comma).
- Clipboard is deliberately manual (`<space>y`/`<space>p`), not synced to the system clipboard.
- Theme background `#1c1c1c` intentionally matches Ghostty.
