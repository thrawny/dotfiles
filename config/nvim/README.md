# Neovim

This is a Lua-configured LazyVim setup packaged immutably with
[`lazy-nvim-nix`](https://github.com/josh/lazy-nvim-nix). LazyVim, plugins, and
Treesitter parsers are Nix store paths; startup performs no plugin installation
or update. Language servers and formatters remain in the shared Home Manager
package sets so agents and shell workflows can use the same tools.

- `nix/lib/nvim-package.nix` selects LazyVim extras and external plugin sources.
- `lua/config/` and `lua/plugins/` keep the normal LazyVim configuration model.
- `nix/flake.lock` is the only plugin/source lock file.

Run `just test-nvim` from the repository root to build the package and execute
the Lua tests. Lua edits take effect after `just switch`; `nix run ./nix#nvim`
builds and launches the pending configuration without switching the profile.

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
