{ config, dotfiles, theme, ... }:
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

  home.file.".config/waybar/theme.css".text =
    let
      palette = theme.palette;
    in
    ''
      :root {
        --waybar-bg: ${palette.backgroundAlpha};
        --waybar-border: ${palette.border};
        --waybar-fg: ${palette.text};
        --waybar-muted: ${palette.textMuted};
        --waybar-accent: ${palette.accent};
        --waybar-warning: ${palette.warning};
      }
    '';
}
