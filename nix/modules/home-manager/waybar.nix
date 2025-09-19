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
          "format-wifi" = "󰤨 {essid}";
          "format-ethernet" = "󰀂";
          "format-disconnected" = "󰖪";
          "tooltip-format-wifi" = "{essid}\n⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
          "tooltip-format-ethernet" = "⇣{bandwidthDownBytes} ⇡{bandwidthUpBytes}";
          interval = 3;
          "on-click" = "ghostty -e nmcli";
        };

        bluetooth = {
          format = "󰂯";
          "format-disabled" = "󰂲";
          "tooltip-format" = "Devices: {num_connections}";
          "on-click" = "ghostty -e bluetoothctl";
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
          format = "{capacity}% {icon}";
          "format-charging" = "󰂄 {capacity}%";
          "format-plugged" = "󰂄";
          "format-icons" = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁿" "󰂁" "󰂂" "󰁹" ];
          "tooltip-format" = "{timeTo}";
          states = {
            warning = 0.20;
            critical = 0.10;
          };
        };

        tray.spacing = 8;
      }
    ];
  };

  home.file.".config/waybar/style.css".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/waybar/style.css";

  home.file.".config/waybar/theme.css".text = ''
    :root {
      --waybar-bg: rgba(28, 28, 28, 0.92);
      --waybar-border: #3a3a3a;
      --waybar-fg: #f0f0f0;
      --waybar-muted: #808080;
      --waybar-accent: #66d9ef;
      --waybar-warning: #f92672;
    }
  '';
}
