_:
let
  # Shared style for both configs
  sharedStyle = ''
    @define-color waybar-bg rgba(28, 28, 28, 0.3);
    @define-color waybar-border #3a3a3a;
    @define-color waybar-fg #f0f0f0;
    @define-color waybar-muted #808080;
    @define-color waybar-accent #66d9ef;
    @define-color waybar-warning #f92672;

    * {
      font-family: "CaskaydiaCove Nerd Font", "JetBrains Mono", sans-serif;
      font-size: 13px;
      color: @waybar-fg;
    }

    window#waybar {
      background-color: @waybar-bg;
      border-bottom: 1px solid @waybar-border;
    }

    #clock,
    #battery,
    #network,
    #pulseaudio,
    #tray,
    #workspaces,
    #idle_inhibitor,
    #language {
      padding: 0 8px;
    }

    #idle_inhibitor.deactivated {
      color: @waybar-muted;
    }

    #idle_inhibitor.activated {
      color: @waybar-accent;
    }

    #workspaces button {
      border: none;
      padding: 0 4px;
      background: transparent;
      color: @waybar-muted;
    }

    /* Hyprland */
    #workspaces button.active {
      color: @waybar-accent;
    }

    /* Niri */
    #workspaces button.focused {
      color: @waybar-accent;
      background: rgba(100, 114, 125, 0.5);
      border-bottom: 3px solid @waybar-accent;
    }

    #battery.warning,
    #battery.critical {
      color: @waybar-warning;
    }

    #battery.critical {
      font-weight: bold;
    }

    #network {
      padding-right: 12px;
    }
  '';

  # Shared modules (work on both compositors)
  sharedModules = {
    clock = {
      format = "{:%Y-%m-%d %H:%M}";
      "format-alt" = "{:%A}";
      tooltip = false;
    };

    network = {
      "format-icons" = [
        "󰤯"
        "󰤟"
        "󰤢"
        "󰤥"
        "󰤨"
      ];
      "format-wifi" = "{icon}";
      "format-ethernet" = "󰀂";
      "format-disconnected" = "󰤮";
      "tooltip-format-wifi" = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
      "tooltip-format-ethernet" = "⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
      "tooltip-format-disconnected" = "Disconnected";
      interval = 3;
      "on-click" = "nm-connection-editor";
    };

    pulseaudio = {
      format = "{icon}";
      "format-muted" = "󰝟";
      "format-icons" = {
        default = [
          "󰕿"
          "󰖀"
          "󰕾"
        ];
        headphones = "󰋋";
        handsfree = "󰋎";
      };
      "tooltip-format" = "{desc}\n{volume}%";
      "scroll-step" = 5;
      "on-click" = "pavucontrol";
    };

    battery = {
      format = "{icon}";
      "format-charging" = "{icon}";
      "format-plugged" = "";
      "format-icons" = {
        charging = [
          "󰢜"
          "󰂆"
          "󰂇"
          "󰂈"
          "󰢝"
          "󰂉"
          "󰢞"
          "󰂊"
          "󰂋"
          "󰂅"
        ];
        default = [
          "󰁺"
          "󰁻"
          "󰁼"
          "󰁽"
          "󰁾"
          "󰁿"
          "󰂀"
          "󰂁"
          "󰂂"
          "󰁹"
        ];
      };
      "format-full" = "󰂅";
      "tooltip-format-discharging" = "{power:>1.0f}W↓ {capacity}%";
      "tooltip-format-charging" = "{power:>1.0f}W↑ {capacity}%";
      interval = 5;
      states = {
        warning = 20;
        critical = 10;
      };
    };

    tray.spacing = 8;

    "idle_inhibitor" = {
      format = "{icon}";
      "format-icons" = {
        activated = "󰅶";
        deactivated = "󰛊";
      };
      tooltip-format-activated = "Caffeine: ON";
      tooltip-format-deactivated = "Caffeine: OFF";
    };
  };
in
{
  programs.waybar = {
    enable = true;

    # Default config for Hyprland
    settings = [
      (
        sharedModules
        // {
          layer = "top";
          position = "top";
          height = 26;
          "modules-left" = [ "hyprland/workspaces" ];
          "modules-center" = [ ];
          "modules-right" = [
            "idle_inhibitor"
            "hyprland/language"
            "tray"
            "network"
            "pulseaudio"
            "battery"
            "clock"
          ];

          "hyprland/workspaces" = {
            on-click = "activate";
            format = "{icon}";
            "format-icons" = {
              default = "";
              active = "";
            };
            "persistent-workspaces" = {
              "1" = [ ];
              "2" = [ ];
              "3" = [ ];
              "4" = [ ];
            };
          };

          "hyprland/language" = {
            format = "{}";
            format-en = "AU";
            format-sv = "SE";
            on-click = "hyprctl switchxkblayout all next";
          };
        }
      )
    ];

    style = sharedStyle;
  };

  # Niri-specific config file
  xdg.configFile."waybar/config-niri".text = builtins.toJSON (
    sharedModules
    // {
      layer = "top";
      position = "top";
      height = 26;
      "modules-left" = [ "niri/workspaces" ];
      "modules-center" = [ "niri/window" ];
      "modules-right" = [
        "idle_inhibitor"
        "niri/language"
        "tray"
        "network"
        "pulseaudio"
        "battery"
        "clock"
      ];

      "niri/window" = {
        format = "{app_id} - {title}";
        max-length = 80;
        tooltip = false;
        rewrite = {
          "com.mitchellh.ghostty - (.*)" = "Ghostty - $1";
          "zen - (.*)" = "Zen Browser - $1";
          "org.gnome.(.*) - (.*)" = "$1 - $2";
          "firefox - (.*)" = "Firefox - $1";
          "Spotify - (.*)" = "Spotify - $1";
          "slack - (.*)" = "Slack - $1";
          "1password - (.*)" = "1Password - $1";
        };
      };

      "niri/language" = {
        format = "{}";
        "format-en" = "AU";
        "format-sv" = "SE";
        "on-click" = "niri msg action switch-layout next";
      };
    }
  );

  xdg.configFile."waybar/style-niri.css".text = sharedStyle;
}
