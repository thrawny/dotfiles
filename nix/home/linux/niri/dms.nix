# DankMaterialShell integration for Niri
# Import after ./default.nix to override bindings and colors
# DMS provides: panel, launcher, lock screen, notifications, wallpaper, OSD
{ lib, ... }:
let
  # DMS catppuccin-style colors
  colors = {
    active = "#cba6f7";
    inactive = "#6c7086";
    urgent = "#f2b8b5";
    shadow = "#00000070";
  };

  # Binds that override base niri config need lib.mkForce
  dmsBinds = {
    # Override launcher to use DMS spotlight
    "Super+Space".action = lib.mkForce {
      spawn = [
        "dms"
        "ipc"
        "call"
        "spotlight"
        "toggle"
      ];
    };

    # Override lock screen to use DMS
    "Mod+Escape".action = lib.mkForce {
      spawn = [
        "dms"
        "ipc"
        "call"
        "lock"
        "lock"
      ];
    };

    # Override Ctrl+Alt+Delete (reboot -> task manager)
    "Ctrl+Alt+Delete".action = lib.mkForce {
      spawn = [
        "dms"
        "ipc"
        "call"
        "processlist"
        "focusOrToggle"
      ];
    };

    # DMS-specific features (new binds, no override needed)
    "Mod+Shift+C" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "clipboard"
        "toggle"
      ];
      hotkey-overlay.title = "Clipboard Manager";
    };
    "Mod+Shift+Comma" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "settings"
        "focusOrToggle"
      ];
      hotkey-overlay.title = "Settings";
    };
    "Mod+Y" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "dankdash"
        "wallpaper"
      ];
      hotkey-overlay.title = "Browse Wallpapers";
    };
    "Mod+Shift+N" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "notepad"
        "toggle"
      ];
      hotkey-overlay.title = "Notepad";
    };
    "Mod+Shift+Z" = {
      action.spawn = [
        "sh"
        "-c"
        "dms ipc call lock lock && systemctl suspend"
      ];
      hotkey-overlay.title = "Lock and Sleep";
    };

    # Audio Controls (DMS OSD) - override base wpctl binds
    "XF86AudioRaiseVolume" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "audio"
          "increment"
          "3"
        ];
      };
      allow-when-locked = true;
    };
    "XF86AudioLowerVolume" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "audio"
          "decrement"
          "3"
        ];
      };
      allow-when-locked = true;
    };
    "XF86AudioMute" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "audio"
          "mute"
        ];
      };
      allow-when-locked = true;
    };
    "XF86AudioMicMute" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "audio"
          "micmute"
        ];
      };
      allow-when-locked = true;
    };

    # Brightness Controls (DMS OSD) - override base brightnessctl binds
    "XF86MonBrightnessUp" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "brightness"
          "increment"
          "5"
          ""
        ];
      };
      allow-when-locked = true;
    };
    "XF86MonBrightnessDown" = {
      action = lib.mkForce {
        spawn = [
          "dms"
          "ipc"
          "call"
          "brightness"
          "decrement"
          "5"
          ""
        ];
      };
      allow-when-locked = true;
    };

    # Extra screenshot keys (new binds)
    "XF86Launch1".action.screenshot = [ ];
    "Ctrl+XF86Launch1".action.screenshot-screen = [ ];
    "Alt+XF86Launch1".action.screenshot-window = [ ];
  };
in
{
  # Don't need swaybg with DMS (it handles wallpaper)
  home.packages = lib.mkForce [ ];

  programs.niri.settings = {
    # Override layout with DMS colors and smaller gaps
    layout = {
      gaps = lib.mkForce 4;
      border = {
        active.color = lib.mkForce colors.active;
        inactive.color = lib.mkForce colors.inactive;
        urgent.color = lib.mkForce colors.urgent;
      };
      shadow.color = lib.mkForce colors.shadow;
    };

    # Remove non-DMS startup apps (DMS handles these)
    spawn-at-startup = lib.mkForce [
      { command = [ "xwayland-satellite" ]; }
      {
        command = [
          "bash"
          "-c"
          "wl-paste --watch cliphist store &"
        ];
      }
      { command = [ "ghostty" ]; }
      { command = [ "zen" ]; }
    ];

    # Merge DMS bindings (overrides base bindings)
    binds = dmsBinds;
  };
}
