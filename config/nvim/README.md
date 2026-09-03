# Neovim

This Lua-configured LazyVim setup has two package paths.

The Nix path uses [`lazy-nvim-nix`](https://github.com/josh/lazy-nvim-nix). Plugins and Treesitter parsers are immutable store paths, while language servers and formatters come from Home Manager. `nix/lib/nvim-package.nix` selects extras and plugin sources; `nix/flake.lock` pins them.

The portable macOS path starts at `init.lua`, bootstraps `lazy.nvim`, and uses `lazy-lock.json`. Mason installs its language servers and formatters. `lua/config/lazy.lua` must select the same LazyVim extras as the Nix package.

Both paths use `lua/config/` and `lua/plugins/`. Run `just test-nvim` from the repository root to build the Nix package and execute the Lua tests. Lua edits on Nix take effect after `just switch`; `nix run ./nix#nvim` builds and launches the pending configuration without switching the profile.

Update the editor inputs from `nix/` with:

```sh
nix flake update lazy-nvim-nix nvim-auto-save nvim-baml-syntax nvim-codediff \
  nvim-git-conflict nvim-monokai-pro nvim-tmux-navigator
```

For local CodeDiff development, override its source at build time instead of
adding a mutable runtime path:

```sh
nix build ./nix#nvim --override-input nvim-codediff path:/absolute/path/to/codediff.nvim
```
