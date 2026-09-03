# Neovim notes

The Lua configuration supports two package paths. Nix assembles an immutable LazyVim package in `nix/lib/nvim-package.nix`. Portable macOS bootstraps `lazy.nvim` from `init.lua`, pins plugins in `lazy-lock.json`, and uses Mason for editor tools.

Keep LazyVim extras aligned between `nix/lib/nvim-package.nix` and `lua/config/lazy.lua`. Plugin behavior belongs in `lua/plugins/`. A Nix-only package override must detect the `/nix/store` program path so Homebrew Neovim keeps its runtime installer.

After portable bootstrap changes, run an unwrapped Neovim sync and `just test-nvim`.

Preferences:

- Leader key is `,` (comma).
- Clipboard is deliberately manual (`<space>y`/`<space>p`), not synced to the system clipboard.
- Colors come from the central theme (`nix/themes/monokai.json`), injected at build time via `vim.g.dotfiles_theme_path` and loaded by `lua/config/theme.lua` — no color literals in the Lua config. The editor background (`semantic.background`, `#222222`) is deliberately a shade lighter than Ghostty's `#1c1c1c`.
