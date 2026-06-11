{ config, ... }:
let
  homeDir = config.home.homeDirectory;
  # Shared style for both configs
  sharedStyle = ''
    @define-color waybar-bg rgba(18, 20, 24, 0.68);
    @define-color waybar-surface rgba(38, 42, 49, 0.62);
    @define-color waybar-border rgba(136, 150, 160, 0.18);
    @define-color waybar-fg #e8e6df;
    @define-color waybar-muted #9aa0a6;
    @define-color waybar-accent #f92672;
    @define-color waybar-accent-2 #fd971f;
    @define-color waybar-warning #f92672;

    * {
      font-family: "CaskaydiaMono Nerd Font", "JetBrains Mono", sans-serif;
      font-size: 13px;
      font-weight: 700;
      color: @waybar-fg;
    }

    window#waybar {
      background: linear-gradient(90deg, rgba(18, 20, 24, 0.76), rgba(26, 28, 33, 0.58));
      border-bottom: 1px solid @waybar-border;
    }

    #clock,
    #battery,
    #network,
    #wireplumber,
    #tray,
    #workspaces,
    #custom-caffeine,
    #language {
      padding: 0 8px;
    }

    #custom-caffeine.deactivated {
      color: @waybar-muted;
    }

    #custom-caffeine.activated {
      color: @waybar-accent;
    }


    #workspaces {
      padding: 3px 5px;
    }

    #workspaces button {
      min-height: 0;
      margin: 0 1px;
      padding: 1px 7px;
      border: 1px solid transparent;
      border-radius: 999px;
      background: transparent;
      color: @waybar-muted;
      font-weight: 700;
      transition: all 180ms ease;
    }

    #workspaces button:hover {
      background: @waybar-surface;
      border-color: rgba(232, 230, 223, 0.12);
      color: @waybar-fg;
    }

    /* Niri */
    #workspaces button.focused,
    #workspaces button.active {
      color: #050505;
      background: linear-gradient(110deg, @waybar-accent 0%, @waybar-accent 42%, @waybar-accent-2 100%);
      border-color: rgba(249, 38, 114, 0.34);
      box-shadow: 0 0 8px rgba(249, 38, 114, 0.18);
    }

    #workspaces button.focused *,
    #workspaces button.active * {
      color: #050505;
      text-shadow: none;
    }

    #workspaces button.focused:hover *,
    #workspaces button.active:hover * {
      color: #050505;
    }

    #workspaces button.urgent {
      color: #111318;
      background: @waybar-warning;
      border-color: rgba(255, 255, 255, 0.24);
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

    #custom-quotabar {
      padding: 0 8px;
    }

    #custom-quotabar.warning {
      color: #e6db74;
    }

    #custom-quotabar.critical {
      color: @waybar-warning;
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

    wireplumber = {
      format = "{icon}";
      "format-muted" = "󰝟";
      "format-icons" = [
        "󰕿"
        "󰖀"
        "󰕾"
      ];
      "tooltip-format" = "{node_name}\n{volume}%";
      "scroll-step" = 5;
      "on-click" = "pavucontrol";
    };

    battery = {
      format = "{icon} {capacity}%";
      "format-charging" = "{icon} {capacity}%";
      "format-not-charging" = "{icon} {capacity}%";
      "format-plugged" = "{icon} {capacity}%";
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
      "format-full" = "󰂅 {capacity}%";
      "tooltip-format-discharging" = "{power:>1.0f}W↓ {capacity}%";
      "tooltip-format-charging" = "{power:>1.0f}W↑ {capacity}%";
      "tooltip-format-not-charging" = "AC connected • {capacity}%";
      interval = 5;
      states = {
        warning = 20;
        critical = 10;
      };
    };

    tray.spacing = 8;

    "custom/quotabar" = {
      exec = "${homeDir}/.cargo/bin/quotabar waybar";
      return-type = "json";
      interval = 60;
      on-click = "${homeDir}/.cargo/bin/quotabar popup";
    };

    "custom/caffeine" = {
      exec = "${homeDir}/dotfiles/bin/caffeine status";
      return-type = "json";
      interval = "once";
      signal = 8;
      on-click = "${homeDir}/dotfiles/bin/caffeine toggle";
    };
  };
in
{
  programs.waybar = {
    enable = true;
    # No default config - using Niri-specific config below
    settings = [ ];
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
      "niri/workspaces" = {
        format = "{icon} {value}";
        "format-icons" = {
          main = "󰧨";
          web = "󰖟";
          dotfiles = "󰚩";
          default = "";
        };
      };
      "modules-right" = [
        "custom/quotabar"
        "custom/caffeine"
        "niri/language"
        "tray"
        "network"
        "wireplumber"
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
