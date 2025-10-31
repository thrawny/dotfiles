# Neovim Configuration Guide

## Making Changes

### Adding LazyVim Extras

Add extras in `lua/config/lazy.lua` (NOT `lazyvim.json`):

```lua
{ import = "lazyvim.plugins.extras.lang.python" },
```

Browse available extras: https://www.lazyvim.org/extras

### Configuration Files

- `lua/config/options.lua` - Editor settings (leader key, clipboard, autoread)
- `lua/config/keymaps.lua` - Custom keybindings
- `lua/config/autocmds.lua` - Auto commands (file reload, terminal cleanup)
- `lua/config/lazy.lua` - Plugin manager setup and extras

### Plugin Customizations

Create/edit files in `lua/plugins/`:
- `theme.lua` - Monokai-nightasty color scheme
- `ui.lua` - UI tweaks (bufferline, snacks)
- `conform.lua` - Formatting config
- `lint.lua` - Linting config
- `autosave.lua` - Auto-save behavior
- `tmux-navigator.lua` - Tmux integration

### Key Settings

- **Leader key**: `,` (comma) - set in `options.lua`
- **Python LSP**: basedpyright - set in `options.lua`
- **Clipboard**: Manual mode (`<space>y`/`<space>p`) - set in `options.lua`
- **Theme background**: `#1c1c1c` (matches Ghostty) - set in `theme.lua`
