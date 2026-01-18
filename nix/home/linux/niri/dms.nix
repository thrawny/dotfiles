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

  dmsBinds = {
    # Override launcher to use DMS spotlight
    "Super+Space" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "spotlight"
        "toggle"
      ];
      hotkey-overlay.title = "Application Launcher";
    };

    # Override lock screen to use DMS
    "Mod+Escape" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "lock"
        "lock"
      ];
      hotkey-overlay.title = "Lock Screen";
    };

    # DMS-specific features
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
    "Ctrl+Alt+Delete" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "processlist"
        "focusOrToggle"
      ];
      hotkey-overlay.title = "Task Manager";
    };

    # Audio Controls (DMS OSD)
    "XF86AudioRaiseVolume" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "audio"
        "increment"
        "3"
      ];
      allow-when-locked = true;
    };
    "XF86AudioLowerVolume" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "audio"
        "decrement"
        "3"
      ];
      allow-when-locked = true;
    };
    "XF86AudioMute" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "audio"
        "mute"
      ];
      allow-when-locked = true;
    };
    "XF86AudioMicMute" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "audio"
        "micmute"
      ];
      allow-when-locked = true;
    };

    # Brightness Controls (DMS OSD)
    "XF86MonBrightnessUp" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "brightness"
        "increment"
        "5"
        ""
      ];
      allow-when-locked = true;
    };
    "XF86MonBrightnessDown" = {
      action.spawn = [
        "dms"
        "ipc"
        "call"
        "brightness"
        "decrement"
        "5"
        ""
      ];
      allow-when-locked = true;
    };

    # Extra screenshot keys
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
