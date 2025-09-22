{ ... }:
{
  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 26;
        "modules-left" = [ "hyprland/workspaces" ];
        "modules-center" = [ ];
        "modules-right" = [
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
            default = "";
            active = "";
          };
          "persistent-workspaces" = {
            "1" = [ ];
            "2" = [ ];
            "3" = [ ];
            "4" = [ ];
          };
        };

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
      }
    ];

    style = ''
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
      #workspaces {
        padding: 0 8px;
      }

      #workspaces button {
        border: none;
        padding: 0 4px;
        background: transparent;
        color: @waybar-muted;
      }

      #workspaces button.active {
        color: @waybar-accent;
      }

      #battery.warning,
      #battery.critical {
        color: @waybar-warning;
      }

      #battery.critical {
        font-weight: bold;
      }

      /* Add spacing after network icon */
      #network {
        padding-right: 12px;
      }
    '';
  };
}
