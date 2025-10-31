# Per-Workspace Drawer Terminal for Hyprland (NixOS)

## Overview

This guide shows how to implement a per-workspace drawer terminal in your NixOS Hyprland setup, similar to the tmux drawer terminal you already have configured. Each workspace gets its own independent drawer terminal with persistent tmux sessions.

**Your Setup:**
- **OS**: NixOS with Home Manager (flake-based)
- **Window Manager**: Hyprland (configured in `nix/home/nixos/hyprland/`)
- **Terminal**: Ghostty (configured in `nix/home/shared/ghostty.nix`)
- **Mod Key**: ALT (set in `nix/home/nixos/hyprland/default.nix`)
- **Existing Packages**: tmux, jq already installed

## Background: tmux Implementation

This builds on your existing tmux drawer terminal:
- **Script**: `bin/tmux-toggle-drawer`
- **Config**: `config/tmux/tmux.conf:126`
- **Keybinding**: `Ctrl+\`` (no prefix)
- **Features**: Per-window persistent sessions, nvim-aware, hidden from switcher

## Implementation Options

You have two options for Hyprland:

1. **Native Bash Script** - Zero dependencies, simple, reliable (just like your tmux drawer)
2. **Pyprland** - More features (auto-hide, TOML config, better animations)

---

## Option 1: Native Bash Script (Recommended to Start)

### Architecture

Creates per-workspace drawers by:
1. Detecting current workspace ID via `hyprctl`
2. Creating unique special workspace: `dropdown-{workspace_id}`
3. Spawning Ghostty with unique class: `dropdown-term-{workspace_id}`
4. Running persistent tmux session: `dropdown-{workspace_id}`

### Implementation

#### Step 1: Create the Toggle Script

Create `bin/hypr-toggle-drawer`:

```bash
#!/usr/bin/env bash
# Toggle per-workspace drawer terminal in Hyprland
# Similar to tmux drawer: each workspace gets its own independent terminal

set -e

# Get current workspace ID
current_ws=$(hyprctl activeworkspace -j | jq -r '.id')
special_name="dropdown-${current_ws}"
class_name="dropdown-term-${current_ws}"

# Check if terminal already exists for this workspace
if hyprctl clients -j | jq -e ".[] | select(.class == \"$class_name\")" > /dev/null 2>&1; then
    # Terminal exists, toggle it
    hyprctl dispatch togglespecialworkspace "$special_name"
else
    # Terminal doesn't exist, create it
    # Launch Ghostty with unique class and connect to per-workspace tmux session
    hyprctl dispatch exec "[workspace special:$special_name] ghostty --class $class_name -e tmux new -A -s dropdown-$current_ws"
    # Give it a moment to spawn, then show it
    sleep 0.1
    hyprctl dispatch togglespecialworkspace "$special_name"
fi
```

Make it executable:
```bash
chmod +x bin/hypr-toggle-drawer
```

#### Step 2: Configure Hyprland via Home Manager

Add or update `nix/home/nixos/hyprland/drawer.nix`:

```nix
{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    # Keybinding: ALT + ` (backtick/grave)
    bind = [
      "ALT, grave, exec, ~/dotfiles/bin/hypr-toggle-drawer"
    ];

    # Window rules for all dropdown terminals
    windowrulev2 = [
      "float, class:^(dropdown-term-)"
      "size 100% 30%, class:^(dropdown-term-)"
      "move 0% 70%, class:^(dropdown-term-)"
    ];

    # Animation for special workspaces (smooth slide from bottom)
    animation = [
      "specialWorkspace, 1, 3, default, slidevert"
    ];

    # Visual settings for special workspaces
    decoration = {
      dim_special = 0;  # Don't dim the dropdown terminal
      blur.special = false;  # Disable blur for better performance
    };

    # Scale factor for special workspaces (1 = full size)
    dwindle.special_scale_factor = 1;
  };
}
```

Import in `nix/home/nixos/hyprland/default.nix`:

```nix
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./autostart.nix
    ./bindings.nix
    ./drawer.nix        # <-- Add this line
    ./envs.nix
    ./input.nix
    ./looknfeel.nix
    ./monitors.nix
    ./windows.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    settings."$mod" = "ALT";
  };
}
```

#### Step 3: Rebuild

```bash
mise switch  # Uses your existing mise task
# Or directly:
# sudo nixos-rebuild switch --flake ./nix#thinkpad
```

#### Step 4: Test

Press `ALT + \`` to toggle the drawer terminal!

### Optional: Add Ghostty Transparency

For a more "overlay" feel, update `nix/home/shared/ghostty.nix`:

```nix
{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isLinux then pkgs.ghostty else null;
    settings = {
      theme = "Molokai";
      background = "#1c1c1c";
      foreground = "#F0F0F0";
      font-family = "CaskaydiaMono Nerd Font";
      font-size = 9;
      window-padding-x = 10;
      window-padding-y = 5;
      cursor-style-blink = false;
      font-synthetic-style = false;
      minimum-contrast = 1.2;
      selection-background = "#49483e";
      selection-foreground = "#f8f8f2";

      # Add transparency for drawer terminals
      background-opacity = 0.85;  # <-- Add this line

      palette = [
        "0=#5c5c5c"
        "8=#808080"
      ];
      keybind = [
        "shift+enter=text:\\n"
      ];
    };
  };
}
```

---

## Option 2: Pyprland Implementation

For advanced features like auto-hide on focus loss and better animation control.

### Step 1: Add Pyprland Package

Add to `nix/home/shared/packages.nix`:

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # ... existing packages ...
    python313Packages.pyprland  # <-- Add this line
  ];
}
```

### Step 2: Create Toggle Script and Config

#### Create the Python toggle script

Add to `pyproject.toml`:

```toml
[project.scripts]
claude-work-timer = "claude_tools.work_timer:cli_main"
claude-loop = "claude_tools.simple_loop:cli_main"
hypr-toggle-drawer-pypr = "claude_tools.hypr_drawer:main"  # <-- Add this
```

Create `claude_tools/hypr_drawer.py`:

```python
#!/usr/bin/env python3
"""Toggle per-workspace drawer terminal using pyprland."""

import json
import subprocess
import sys


def get_current_workspace() -> int:
    """Get the current workspace ID."""
    result = subprocess.run(
        ["hyprctl", "activeworkspace", "-j"],
        capture_output=True,
        text=True,
        check=True,
    )
    workspace = json.loads(result.stdout)
    return workspace["id"]


def toggle_drawer(workspace_id: int) -> None:
    """Toggle the drawer for the specified workspace."""
    scratchpad_name = f"term-{workspace_id}"
    subprocess.run(["pypr", "toggle", scratchpad_name], check=False)


def main() -> None:
    """Main entry point."""
    try:
        workspace_id = get_current_workspace()
        toggle_drawer(workspace_id)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

#### Or use a simple bash script

Alternatively, create `bin/hypr-toggle-drawer-pypr`:

```bash
#!/usr/bin/env bash
# Toggle per-workspace drawer using pyprland

set -e

# Get current workspace ID
current_ws=$(hyprctl activeworkspace -j | jq -r '.id')
scratchpad_name="term-${current_ws}"

# Toggle the workspace-specific scratchpad
pypr toggle "$scratchpad_name"
```

Make it executable:
```bash
chmod +x bin/hypr-toggle-drawer-pypr
```

#### Create pyprland config

Create `config/hypr/pyprland.toml`:

```toml
[pyprland]
plugins = ["scratchpads"]

# Define scratchpads for first 10 workspaces
[scratchpads.term-1]
command = "ghostty --class dropdown-term-1 -e tmux new -A -s dropdown-1"
class = "dropdown-term-1"
size = "100% 30%"
animation = "fromBottom"
margin = 0
unfocus = "hide"  # Auto-hide when focus is lost (optional)

[scratchpads.term-2]
command = "ghostty --class dropdown-term-2 -e tmux new -A -s dropdown-2"
class = "dropdown-term-2"
size = "100% 30%"
animation = "fromBottom"
margin = 0
unfocus = "hide"

# ... repeat for term-3 through term-10
# Or generate this file - see helper below
```

**Helper to generate the config** - add to `pyproject.toml`:

```toml
[project.scripts]
generate-pyprland-drawers = "claude_tools.generate_pyprland:main"
```

Create `claude_tools/generate_pyprland.py`:

```python
#!/usr/bin/env python3
"""Generate pyprland.toml config for N workspace drawers."""

import sys


def generate_config(num_workspaces: int = 10) -> None:
    """Generate pyprland config for specified number of workspaces."""
    print("[pyprland]")
    print('plugins = ["scratchpads"]')
    print()

    for i in range(1, num_workspaces + 1):
        print(f"[scratchpads.term-{i}]")
        print(f'command = "ghostty --class dropdown-term-{i} -e tmux new -A -s dropdown-{i}"')
        print(f'class = "dropdown-term-{i}"')
        print('size = "100% 30%"')
        print('animation = "fromBottom"')
        print('margin = 0')
        print('unfocus = "hide"  # Auto-hide when focus is lost')
        print()


def main() -> None:
    """Main entry point."""
    num = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    generate_config(num)


if __name__ == "__main__":
    main()
```

Usage:
```bash
uv run generate-pyprland-drawers 20 > config/hypr/pyprland.toml
```

### Step 3: Configure Hyprland

Create `nix/home/nixos/hyprland/drawer-pypr.nix`:

```nix
{ lib, config, ... }:
{
  # Symlink pyprland config
  xdg.configFile."hypr/pyprland.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/config/hypr/pyprland.toml";

  wayland.windowManager.hyprland.settings = {
    # Start pyprland daemon
    exec-once = [ "pypr" ];

    # Keybinding (adjust path based on whether you use Python or bash script)
    bind = [
      # If using Python script from pyproject.toml:
      "ALT, grave, exec, hypr-toggle-drawer-pypr"
      # Or if using bash script:
      # "ALT, grave, exec, ~/dotfiles/bin/hypr-toggle-drawer-pypr"
    ];

    # Window rules (optional, pyprland manages most of this)
    windowrulev2 = [
      "float, class:^(dropdown-term-)"
    ];
  };
}
```

Import in `nix/home/nixos/hyprland/default.nix`:

```nix
imports = [
  # ...
  ./drawer-pypr.nix  # <-- Add this
];
```

### Step 4: Rebuild

```bash
mise switch
```

### Pyprland Features

#### Auto-hide on Focus Loss

Edit `config/hypr/pyprland.toml`:
```toml
[scratchpads.term-1]
unfocus = "hide"  # Hide when focus is lost
# OR
unfocus = "none"  # Keep visible
```

#### Position Hysteresis

```toml
[scratchpads.term-1]
hysteresis = 1.0  # Remember position per workspace
```

#### Max Size Limits

```toml
[scratchpads.term-1]
max_size = "1920px 400px"
```

---

## Comparison with tmux Implementation

| Feature | tmux Drawer | Hyprland Native | Hyprland Pyprland |
|---------|-------------|-----------------|-------------------|
| **Per-workspace** | ✅ Per tmux window | ✅ Per Hyprland workspace | ✅ Per Hyprland workspace |
| **Persistent sessions** | ✅ `drawer-w@{id}` | ✅ `dropdown-{id}` | ✅ `dropdown-{id}` |
| **Toggle key** | Ctrl+\` (no prefix) | ALT+\` | ALT+\` |
| **Position** | Bottom split (30%) | Bottom float (30%) | Bottom float (30%) |
| **Auto-hide** | ❌ Manual close | ❌ Manual close | ✅ Optional |
| **Configuration** | Bash + tmux.conf | Nix module | Nix module + TOML |
| **Dependencies** | tmux only | tmux, jq, hyprland | tmux, jq, pyprland |
| **Daemon** | ❌ No | ❌ No | ✅ pypr |

---

## Integration with Existing Setup

### Keybinding Conflicts

Your current bindings (from `nix/home/nixos/hyprland/bindings.nix`):
- `${mod}, S` - Toggle special workspace "magic"
- `${mod}, RETURN` - Launch Ghostty

The drawer uses `ALT, grave` which doesn't conflict with any existing bindings.

### Custom Mod Key Alternative

If you want to use a different key:

```nix
# In your drawer module
bind = [
  # Use Super (Windows key) instead
  "SUPER, grave, exec, ${hypr-toggle-drawer}/bin/hypr-toggle-drawer"

  # Or Ctrl
  "CTRL, grave, exec, ${hypr-toggle-drawer}/bin/hypr-toggle-drawer"
];
```

### Adjusting Size

Change window rules in the module:

```nix
windowrulev2 = [
  "float, class:^(dropdown-term-)"
  "size 100% 40%, class:^(dropdown-term-)"  # 40% instead of 30%
  "move 0% 60%, class:^(dropdown-term-)"    # Adjust Y position
];
```

### nvim Awareness (Optional)

To replicate tmux's nvim-aware behavior, modify the script:

```nix
hypr-toggle-drawer = pkgs.writeShellScriptBin "hypr-toggle-drawer" ''
  #!/usr/bin/env bash
  set -e

  # Get current workspace and active window
  current_ws=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r '.id')
  active_window=$(${pkgs.hyprland}/bin/hyprctl activewindow -j)
  window_class=$(echo "$active_window" | ${pkgs.jq}/bin/jq -r '.class')
  window_title=$(echo "$active_window" | ${pkgs.jq}/bin/jq -r '.title')

  # Check if nvim is running in the active window
  if echo "$window_class $window_title" | ${pkgs.gnugrep}/bin/grep -qi "nvim"; then
      # nvim is active, don't toggle drawer
      exit 0
  fi

  # Continue with normal drawer toggle...
  special_name="dropdown-''${current_ws}"
  class_name="dropdown-term-''${current_ws}"

  if ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e ".[] | select(.class == \"$class_name\")" > /dev/null 2>&1; then
      ${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace "$special_name"
  else
      ${pkgs.hyprland}/bin/hyprctl dispatch exec "[workspace special:$special_name] ${pkgs.ghostty}/bin/ghostty --class $class_name -e ${pkgs.tmux}/bin/tmux new -A -s dropdown-$current_ws"
      sleep 0.1
      ${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace "$special_name"
  fi
'';
```

---

## Troubleshooting

### Drawer doesn't appear

Check if the script is in your PATH:
```bash
which hypr-toggle-drawer
```

Test the script directly:
```bash
hypr-toggle-drawer
```

View Hyprland logs:
```bash
journalctl --user -xe | grep hypr
```

### Terminal spawns but doesn't show

Increase sleep delay in the Nix module:
```nix
sleep 0.2  # Instead of 0.1
```

### Keybinding not working

Check Hyprland config was applied:
```bash
hyprctl binds | grep grave
```

Reload Hyprland:
```bash
hyprctl reload
```

### After NixOS rebuild, drawer doesn't work

The special workspaces and terminal processes persist after rebuild. Either:
1. Kill old terminals: `pkill -f "dropdown-term"`
2. Restart Hyprland: `hyprctl dispatch exit` (then login again)

---

## Session Management

### List all drawer tmux sessions

```bash
tmux list-sessions | grep "^dropdown-"
```

### Manually attach to a workspace's drawer

```bash
# For workspace 1's drawer
tmux attach-session -t dropdown-1

# For workspace 5's drawer
tmux attach-session -t dropdown-5
```

### Clean up unused drawer sessions

```bash
# Kill all drawer sessions
tmux list-sessions | grep "^dropdown-" | cut -d: -f1 | xargs -I {} tmux kill-session -t {}

# Kill specific workspace drawer
tmux kill-session -t dropdown-3
```

### View all active drawer terminals

```bash
hyprctl clients | grep "dropdown-term-"
```

---

## Integration with mise Tasks

Add a task to `mise.toml` for managing drawer sessions:

```toml
[tasks.drawer-clean]
description = "Clean up unused Hyprland drawer sessions"
run = "tmux list-sessions | grep '^dropdown-' | cut -d: -f1 | xargs -I {} tmux kill-session -t {}"

[tasks.drawer-list]
description = "List all active drawer sessions"
run = "tmux list-sessions | grep '^dropdown-'"
```

Usage:
```bash
mise drawer-clean  # Clean up old sessions
mise drawer-list   # View active drawers
```

---

## File Structure

Your final structure will look like:

```
dotfiles/
├── bin/
│   ├── tmux-toggle-drawer              # Existing tmux drawer
│   ├── hypr-toggle-drawer              # Native Hyprland drawer (bash)
│   └── hypr-toggle-drawer-pypr         # Pyprland drawer (bash, optional)
├── config/
│   ├── hypr/
│   │   └── pyprland.toml               # Pyprland config (if using)
│   └── tmux/
│       └── tmux.conf
├── claude_tools/
│   ├── hypr_drawer.py                  # Python toggle script (optional)
│   └── generate_pyprland.py            # Config generator (optional)
├── nix/
│   └── home/
│       ├── nixos/
│       │   └── hyprland/
│       │       ├── default.nix         # Import drawer.nix here
│       │       ├── drawer.nix          # Native drawer config
│       │       ├── drawer-pypr.nix     # Pyprland config (optional)
│       │       └── ...
│       └── shared/
│           ├── ghostty.nix             # Add transparency here (optional)
│           └── packages.nix            # Add pyprland here (if using)
└── pyproject.toml                      # Add scripts here (optional)
```

---

## Quick Start Checklist

**For Native Bash Implementation:**
- [ ] Create `bin/hypr-toggle-drawer` script
- [ ] Make it executable: `chmod +x bin/hypr-toggle-drawer`
- [ ] Create `nix/home/nixos/hyprland/drawer.nix`
- [ ] Import in `nix/home/nixos/hyprland/default.nix`
- [ ] Run `mise switch` to rebuild
- [ ] Test with `ALT + \``
- [ ] (Optional) Add transparency to `nix/home/shared/ghostty.nix`

**For Pyprland Implementation:**
- [ ] Add `python313Packages.pyprland` to `nix/home/shared/packages.nix`
- [ ] Create toggle script (either Python in `claude_tools/` or bash in `bin/`)
- [ ] Generate `config/hypr/pyprland.toml` (manually or with helper)
- [ ] Create `nix/home/nixos/hyprland/drawer-pypr.nix`
- [ ] Import in `nix/home/nixos/hyprland/default.nix`
- [ ] Run `mise switch` to rebuild
- [ ] Test with `ALT + \``

---

## Recommendation

**Start with the Native Bash Script** implementation:
- Simpler, fewer dependencies
- No daemon to manage
- Easy to debug
- Fast and reliable

**Upgrade to Pyprland later** if you want:
- Auto-hide on focus loss
- Multiple scratchpads (notes, music, etc.)
- Better animation control
- TOML-based configuration

Both provide per-workspace drawer terminals with persistent tmux sessions, just like your existing tmux drawer!

---

**Last Updated**: 2025-10-31
**Tested On**: NixOS 24.05+ with Hyprland via Home Manager
**Your Setup**: Flake-based NixOS with Ghostty, tmux, and Hyprland
