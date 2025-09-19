{ config, dotfiles, ... }:
{
  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 26;
        "modules-left" = [ "hyprland/workspaces" ];
        "modules-center" = [ "clock" ];
        "modules-right" = [ "tray" "network" "bluetooth" "pulseaudio" "battery" ];

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
          format = "{:%A %H:%M}";
          "format-alt" = "{:%Y-%m-%d}";
          tooltip = false;
        };

        network = {
          "format-icons" = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
          "format-wifi" = "{icon}";
          "format-ethernet" = "󰀂";
          "format-disconnected" = "󰤮";
          "tooltip-format-wifi" = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
          "tooltip-format-ethernet" = "⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
          "tooltip-format-disconnected" = "Disconnected";
          interval = 3;
          "on-click" = "nm-connection-editor";
        };

        bluetooth = {
          format = "󰂯";
          "format-disabled" = "󰂲";
          "format-connected" = "󰂱";
          "tooltip-format" = "Devices connected: {num_connections}";
          "on-click" = "blueman-manager";
        };

        pulseaudio = {
          format = "{icon}";
          "format-muted" = "󰝟";
          "format-icons" = {
            default = [ "󰕿" "󰖀" "󰕾" ];
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
            charging = [ "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅" ];
            default = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
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
  };

  home.file.".config/waybar/style.css".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/waybar/style.css";
}
