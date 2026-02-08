# Base Niri window manager configuration
# Import this for any Linux system using niri
# Add ./dms.nix for DankMaterialShell integration
# Add ./switcher.nix for agent-switch
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  # Base colors - matching Hyprland Molokai theme
  colors = {
    active = "#f92672";
    inactive = "#3a3a3a";
    urgent = "#cc4444";
    shadow = "#0007";
  };

  baseBinds = {
    # System & Overview
    "Mod+D" = {
      action.toggle-overview = [ ];
      repeat = false;
    };
    "Mod+Shift+Slash".action.show-hotkey-overlay = [ ];

    # Application Launchers
    "Mod+Return" = {
      action.spawn = [ "ghostty" ];
      hotkey-overlay.title = "Open Terminal";
    };
    "Super+Space" = {
      action.spawn = [ "walker" ];
      hotkey-overlay.title = "Application Launcher";
    };
    "Mod+M" = {
      action.focus-window-previous = [ ];
      hotkey-overlay.title = "Previous Window";
    };
    "Mod+N" = {
      action.focus-workspace = 1;
      hotkey-overlay.title = "Workspace 1";
    };
    "Mod+B" = {
      action.focus-workspace = "web";
      hotkey-overlay.title = "Web Workspace";
    };
    "Mod+O" = {
      action.spawn = [ "1password" ];
      hotkey-overlay.title = "1Password";
    };
    "Mod+P" = {
      action.spawn = [ "spotify" ];
      hotkey-overlay.title = "Spotify";
    };
    "Mod+Shift+S" = {
      action.spawn = [ "slack" ];
      hotkey-overlay.title = "Slack";
    };

    # Security
    "Mod+Shift+Escape".action.quit = [ ];
    "Mod+Shift+Ctrl+Delete".action.spawn = [
      "systemctl"
      "poweroff"
    ];
    "Mod+Escape" = {
      action.spawn = [ "hyprlock" ];
      hotkey-overlay.title = "Lock Screen";
    };
    "Ctrl+Alt+Delete".action.spawn = [ "reboot" ];

    # Window Management
    "Mod+W" = {
      action.close-window = [ ];
      repeat = false;
    };
    "Mod+F".action.maximize-column = [ ];
    "Mod+Shift+F".action.fullscreen-window = [ ];
    "Mod+V".action.toggle-window-floating = [ ];
    "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = [ ];
    "Mod+G".action.toggle-column-tabbed-display = [ ];

    # Focus Navigation
    "Mod+Left".action.focus-column-left = [ ];
    "Mod+Down".action.focus-window-down = [ ];
    "Mod+Up".action.focus-window-up = [ ];
    "Mod+Right".action.focus-column-right = [ ];
    "Mod+H".action.focus-column-left = [ ];
    "Mod+J".action.focus-window-down = [ ];
    "Mod+K".action.focus-window-up = [ ];
    "Mod+L".action.focus-column-right = [ ];

    # Window Movement
    "Mod+Shift+Left".action.move-column-left = [ ];
    "Mod+Shift+Down".action.move-window-down = [ ];
    "Mod+Shift+Up".action.move-window-up = [ ];
    "Mod+Shift+Right".action.move-column-right = [ ];
    "Mod+Shift+H".action.move-column-left = [ ];
    "Mod+Shift+J".action.move-window-down = [ ];
    "Mod+Shift+K".action.move-window-up = [ ];
    "Mod+Shift+L".action.move-column-right = [ ];

    # Column Navigation
    "Mod+Home".action.focus-column-first = [ ];
    "Mod+End".action.focus-column-last = [ ];
    "Mod+Ctrl+Home".action.move-column-to-first = [ ];
    "Mod+Ctrl+End".action.move-column-to-last = [ ];

    # Monitor Navigation
    "Mod+Ctrl+Left".action.focus-monitor-left = [ ];
    "Mod+Ctrl+Right".action.focus-monitor-right = [ ];
    "Mod+Ctrl+H".action.focus-monitor-left = [ ];
    "Mod+Ctrl+J".action.focus-monitor-down = [ ];
    "Mod+Ctrl+K".action.focus-monitor-up = [ ];
    "Mod+Ctrl+L".action.focus-monitor-right = [ ];

    # Move Column to Monitor
    "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [ ];
    "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [ ];
    "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [ ];
    "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [ ];
    "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [ ];
    "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [ ];
    "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [ ];
    "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [ ];

    # Move Workspace to Monitor
    "Mod+Super+H".action.move-workspace-to-monitor-left = [ ];
    "Mod+Super+J".action.move-workspace-to-monitor-down = [ ];
    "Mod+Super+K".action.move-workspace-to-monitor-up = [ ];
    "Mod+Super+L".action.move-workspace-to-monitor-right = [ ];

    # Workspace Navigation
    "Mod+Page_Down".action.focus-workspace-down = [ ];
    "Mod+Page_Up".action.focus-workspace-up = [ ];
    "Mod+U".action.focus-workspace-down = [ ];
    "Mod+I".action.focus-workspace-up = [ ];
    "Mod+Comma".action.focus-workspace-up = [ ];
    "Mod+Period".action.focus-workspace-down = [ ];
    "Mod+Ctrl+Down".action.move-column-to-workspace-down = [ ];
    "Mod+Ctrl+Up".action.move-column-to-workspace-up = [ ];
    "Mod+Ctrl+U".action.move-column-to-workspace-down = [ ];
    "Mod+Ctrl+I".action.move-column-to-workspace-up = [ ];

    # Move Workspaces
    "Mod+Shift+Page_Down".action.move-workspace-down = [ ];
    "Mod+Shift+Page_Up".action.move-workspace-up = [ ];
    "Mod+Shift+U".action.move-workspace-down = [ ];
    "Mod+Shift+I".action.move-workspace-up = [ ];

    # Mouse Wheel Navigation
    "Mod+WheelScrollDown" = {
      action.focus-workspace-down = [ ];
      cooldown-ms = 150;
    };
    "Mod+WheelScrollUp" = {
      action.focus-workspace-up = [ ];
      cooldown-ms = 150;
    };
    "Mod+Ctrl+WheelScrollDown" = {
      action.move-column-to-workspace-down = [ ];
      cooldown-ms = 150;
    };
    "Mod+Ctrl+WheelScrollUp" = {
      action.move-column-to-workspace-up = [ ];
      cooldown-ms = 150;
    };
    "Mod+WheelScrollRight".action.focus-column-right = [ ];
    "Mod+WheelScrollLeft".action.focus-column-left = [ ];
    "Mod+Ctrl+WheelScrollRight".action.move-column-right = [ ];
    "Mod+Ctrl+WheelScrollLeft".action.move-column-left = [ ];
    "Mod+Shift+WheelScrollDown".action.focus-column-right = [ ];
    "Mod+Shift+WheelScrollUp".action.focus-column-left = [ ];
    "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = [ ];
    "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = [ ];

    # Numbered Workspaces
    "Mod+1".action.focus-workspace = 1;
    "Mod+2".action.focus-workspace = 2;
    "Mod+3".action.focus-workspace = 3;
    "Mod+4".action.focus-workspace = 4;
    "Mod+5".action.focus-workspace = 5;
    "Mod+6".action.focus-workspace = 6;
    "Mod+7".action.focus-workspace = 7;
    "Mod+8".action.focus-workspace = 8;
    "Mod+9".action.focus-workspace = 9;
    "Mod+0".action.focus-workspace = 10;

    # Move to Numbered Workspaces
    "Mod+Shift+1".action.move-column-to-workspace = 1;
    "Mod+Shift+2".action.move-column-to-workspace = 2;
    "Mod+Shift+3".action.move-column-to-workspace = 3;
    "Mod+Shift+4".action.move-column-to-workspace = 4;
    "Mod+Shift+5".action.move-column-to-workspace = 5;
    "Mod+Shift+6".action.move-column-to-workspace = 6;
    "Mod+Shift+7".action.move-column-to-workspace = 7;
    "Mod+Shift+8".action.move-column-to-workspace = 8;
    "Mod+Shift+9".action.move-column-to-workspace = 9;
    "Mod+Shift+0".action.move-column-to-workspace = 10;

    # Column Management
    "Mod+BracketLeft".action.consume-or-expel-window-left = [ ];
    "Mod+BracketRight".action.consume-or-expel-window-right = [ ];
    "Mod+Shift+Period".action.expel-window-from-column = [ ];

    # Sizing & Layout
    "Mod+Backslash".action.switch-preset-column-width = [ ];
    "Mod+Shift+Backslash".action.switch-preset-window-height = [ ];
    "Mod+Ctrl+R".action.reset-window-height = [ ];
    "Mod+Ctrl+F".action.expand-column-to-available-width = [ ];
    "Mod+C".action.center-column = [ ];
    "Mod+Ctrl+C".action.center-visible-columns = [ ];

    # Voice (voice-to-text)
    "Mod+R" = {
      action.spawn = [
        "voice"
        "toggle"
      ];
      hotkey-overlay.title = "Voice Input Toggle";
      repeat = false;
    };
    "Super+P" = {
      action.spawn = [
        "voice"
        "toggle"
      ];
      hotkey-overlay.title = "Voice Input Toggle";
      repeat = false;
    };
    "Mod+Shift+R" = {
      action.spawn = [
        "voice"
        "cancel"
      ];
      hotkey-overlay.title = "Voice Input Cancel";
    };

    # Manual Sizing
    "Mod+Minus".action.set-column-width = "-10%";
    "Mod+Equal".action.set-column-width = "+10%";
    "Mod+Shift+Minus".action.set-window-height = "-10%";
    "Mod+Shift+Equal".action.set-window-height = "+10%";

    # Screenshots
    "Print".action.screenshot = [ ];
    "Ctrl+Print".action.screenshot-screen = [ ];
    "Alt+Print".action.screenshot-window = [ ];
    "Super+Shift+3".action.screenshot-screen = [ ];
    "Super+Shift+4".action.screenshot = [ ];

    # System Controls
    "Mod+Ctrl+Escape" = {
      action.toggle-keyboard-shortcuts-inhibit = [ ];
      allow-inhibiting = false;
    };
    "Mod+Shift+P".action.power-off-monitors = [ ];
    "Mod+Super+M" = {
      action.spawn = [
        "bash"
        "-c"
        "niri msg output HDMI-A-1 off && sleep 1 && niri msg output HDMI-A-1 on"
      ];
      hotkey-overlay.title = "Wake LG Monitor";
      allow-when-locked = true;
    };

    # Keyboard Layout
    "Mod+Super+Space" = {
      action.switch-layout = "next";
      hotkey-overlay.title = "Switch Keyboard Layout";
    };

    # Audio Controls (wpctl)
    "XF86AudioRaiseVolume" = {
      action.spawn = [
        "wpctl"
        "set-volume"
        "-l"
        "1"
        "@DEFAULT_AUDIO_SINK@"
        "5%+"
      ];
      allow-when-locked = true;
    };
    "XF86AudioLowerVolume" = {
      action.spawn = [
        "wpctl"
        "set-volume"
        "@DEFAULT_AUDIO_SINK@"
        "5%-"
      ];
      allow-when-locked = true;
    };
    "XF86AudioMute" = {
      action.spawn = [
        "wpctl"
        "set-mute"
        "@DEFAULT_AUDIO_SINK@"
        "toggle"
      ];
      allow-when-locked = true;
    };
    "XF86AudioMicMute" = {
      action.spawn = [
        "wpctl"
        "set-mute"
        "@DEFAULT_AUDIO_SOURCE@"
        "toggle"
      ];
      allow-when-locked = true;
    };

    # Brightness Controls
    "XF86MonBrightnessUp" = {
      action.spawn = [
        "brightnessctl"
        "set"
        "5%+"
      ];
      allow-when-locked = true;
    };
    "XF86MonBrightnessDown" = {
      action.spawn = [
        "brightnessctl"
        "set"
        "5%-"
      ];
      allow-when-locked = true;
    };

    # Media Controls (playerctl)
    "XF86AudioPlay" = {
      action.spawn = [
        "playerctl"
        "play-pause"
      ];
      allow-when-locked = true;
    };
    "XF86AudioPause" = {
      action.spawn = [
        "playerctl"
        "play-pause"
      ];
      allow-when-locked = true;
    };
    "XF86AudioNext" = {
      action.spawn = [
        "playerctl"
        "next"
      ];
      allow-when-locked = true;
    };
    "XF86AudioPrev" = {
      action.spawn = [
        "playerctl"
        "previous"
      ];
      allow-when-locked = true;
    };
  };
in
{
  home.packages = [ pkgs.swaybg ];

  programs.niri.settings = {
    # Named workspaces
    workspaces = {
      "main" = { };
      "web" = { };
      "dotfiles" = { };
    };

    # Disable config notification on failure
    config-notification.disable-failed = true;

    # Gestures
    gestures.hot-corners.enable = false;

    # Input
    input = {
      mod-key = "Alt";
      warp-mouse-to-focus.enable = true;
      focus-follows-mouse.enable = true;
      mouse.accel-profile = "flat";
      keyboard = {
        xkb = {
          layout = "au,se";
          options = "caps:escape";
        };
        numlock = true;
        repeat-delay = 200;
        repeat-rate = 30;
      };
      touchpad = {
        natural-scroll = true;
        tap = true;
        scroll-factor = 0.3;
      };
    };

    cursor.size = 16;

    # Layout
    layout = {
      gaps = 8;
      background-color = "transparent";
      center-focused-column = "never";

      preset-column-widths = [
        { proportion = 0.33333; }
        { proportion = 0.5; }
        { proportion = 0.66667; }
      ];

      default-column-width.proportion = 0.5;

      border = {
        enable = true;
        width = 2;
        active.color = colors.active;
        inactive.color = colors.inactive;
        urgent.color = colors.urgent;
      };

      focus-ring.enable = false;

      shadow = {
        softness = 30;
        spread = 5;
        offset = {
          x = 0;
          y = 5;
        };
        color = colors.shadow;
      };
    };

    # Layer rules
    layer-rules = [
      {
        matches = [ { namespace = "^quickshell$"; } ];
        place-within-backdrop = true;
      }
    ];

    # Overview
    overview.workspace-shadow.enable = false;

    # Spawn at startup (xwayland-satellite spawned on-demand by niri)
    spawn-at-startup = [
      {
        command = [
          "bash"
          "-c"
          "wl-paste --watch cliphist store &"
        ];
      }
      { command = [ "ghostty" ]; }
      {
        command = [
          "zen"
          "-p"
          "Default Profile"
        ];
      }
      {
        command = [
          "waybar"
          "-c"
          "${config.home.homeDirectory}/.config/waybar/config-niri"
          "-s"
          "${config.home.homeDirectory}/.config/waybar/style-niri.css"
        ];
      }
      { command = [ "mako" ]; }
      {
        command = [
          "env"
          "VOICE_PASTE_MOD=shift"
          "VOICE_PASTE_KEY=Insert"
          "voice"
          "serve"
        ];
      }
      {
        command = [
          "swaybg"
          "-i"
          "${config.home.homeDirectory}/dotfiles/assets/nasa.jpg"
          "-m"
          "fill"
        ];
      }
    ];

    # Environment
    environment = {
      XDG_CURRENT_DESKTOP = "niri";
      NIXOS_OZONE_WL = "1";
      DISPLAY = ":0";
    };

    hotkey-overlay.skip-at-startup = true;
    prefer-no-csd = true;
    screenshot-path = "~/Screenshots/%Y-%m-%d_%H-%M-%S.png";

    # Animations
    animations = {
      workspace-switch.kind.spring = {
        damping-ratio = 1.0;
        stiffness = 10000;
        epsilon = 0.01;
      };
      horizontal-view-movement.kind.spring = {
        damping-ratio = 0.9;
        stiffness = 800;
        epsilon = 0.0001;
      };
      window-open.kind.easing = {
        duration-ms = 150;
        curve = "ease-out-expo";
      };
      window-close.kind.easing = {
        duration-ms = 150;
        curve = "ease-out-quad";
      };
      window-movement.kind.spring = {
        damping-ratio = 0.75;
        stiffness = 323;
        epsilon = 0.0001;
      };
      window-resize.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 423;
        epsilon = 0.0001;
      };
      config-notification-open-close.kind.spring = {
        damping-ratio = 0.65;
        stiffness = 923;
        epsilon = 0.001;
      };
      screenshot-ui-open.kind.easing = {
        duration-ms = 200;
        curve = "ease-out-quad";
      };
      overview-open-close.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.0001;
      };
    };

    # Window rules
    window-rules = [
      {
        geometry-corner-radius = {
          top-left = 12.0;
          top-right = 12.0;
          bottom-left = 12.0;
          bottom-right = 12.0;
        };
        clip-to-geometry = true;
      }
      {
        matches = [
          { app-id = "^gnome-calculator$"; }
          { app-id = "^galculator$"; }
          { app-id = "blueman-manager"; }
          { app-id = "^nm-connection-editor$"; }
          { app-id = "^org\\.pulseaudio\\.pavucontrol$"; }
          { app-id = "^xdg-desktop-portal"; }
          { app-id = "zoom"; }
          { app-id = "^com\\.thrawny\\.agent-switch$"; }
          { app-id = "^spotify$"; }
          { app-id = "^1password$"; }
        ];
        open-floating = true;
        open-maximized = false;
      }
      {
        matches = [ { is-active = false; } ];
        opacity = 0.9;
      }
    ];

    binds = baseBinds;
  };

  # niri-flake doesn't expose recent-windows settings yet, so append raw KDL
  # to the generated config file. This isn't circular because finalConfig
  # depends on settings/config, not on xdg.configFile.source.
  xdg.configFile.niri-config.source = lib.mkForce (
    pkgs.writeText "niri-config.kdl" ''
      ${config.programs.niri.finalConfig}

      recent-windows {
          debounce-ms 750
          open-delay-ms 150

          highlight {
              active-color "${colors.active}ff"
              urgent-color "${colors.urgent}ff"
          }

          binds {
              Mod+Tab         { next-window; }
              Mod+Shift+Tab   { previous-window; }
          }
      }
    ''
  );
}
