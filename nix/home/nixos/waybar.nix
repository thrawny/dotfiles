{
  config,
  theme,
  themeLib,
  ...
}:
let
  homeDir = config.home.homeDirectory;
  wb = theme.applications.waybar;
  inherit (themeLib) rgb;

  # Shared style for both configs
  sharedStyle = ''
    @define-color waybar-bg rgba(${rgb wb.bg}, 0.68);
    @define-color waybar-surface rgba(${rgb wb.surface}, 0.62);
    @define-color waybar-border rgba(${rgb wb.border}, 0.18);
    @define-color waybar-fg ${wb.fg};
    @define-color waybar-muted ${wb.muted};
    @define-color waybar-accent ${wb.accent};
    @define-color waybar-accent-2 ${wb.accentAlt};
    @define-color waybar-warning ${wb.accent};

    * {
      font-family: "CaskaydiaMono Nerd Font", "JetBrains Mono", sans-serif;
      font-size: 13px;
      font-weight: 700;
      color: @waybar-fg;
    }

    window#waybar {
      background: linear-gradient(90deg, rgba(${rgb wb.bg}, 0.76), rgba(${rgb wb.bgAlt}, 0.58));
      border-bottom: 1px solid @waybar-border;
    }

    #clock,
    #battery,
    #network,
    #wireplumber,
    #tray,
    #workspaces,
    #custom-caffeine,
    #custom-agent-status,
    #language {
      padding: 0 8px;
    }

    /* Sidebar priority: bright Done, sky Working, muted Idle. */
    #custom-agent-status.done {
      color: ${wb.done};
    }

    #custom-agent-status.working {
      color: ${wb.working};
    }

    #custom-agent-status.idle,
    #custom-agent-status.unavailable {
      color: @waybar-muted;
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
      border-color: rgba(${rgb wb.fg}, 0.12);
      color: @waybar-fg;
    }

    /* Niri */
    #workspaces button.focused,
    #workspaces button.active {
      color: ${wb.onAccent};
      background: linear-gradient(110deg, @waybar-accent 0%, @waybar-accent 42%, @waybar-accent-2 100%);
      border-color: rgba(${rgb wb.accent}, 0.34);
      box-shadow: 0 0 8px rgba(${rgb wb.accent}, 0.18);
    }

    #workspaces button.focused *,
    #workspaces button.active * {
      color: ${wb.onAccent};
      text-shadow: none;
    }

    #workspaces button.focused:hover *,
    #workspaces button.active:hover * {
      color: ${wb.onAccent};
    }

    /* On multi-monitor niri, every visible workspace is "active".
       Keep non-focused active workspaces visible without making them look selected. */
    #workspaces button.active:not(.focused) {
      color: @waybar-accent-2;
      background: rgba(${rgb wb.accentAlt}, 0.14);
      border-color: rgba(${rgb wb.accentAlt}, 0.24);
      box-shadow: none;
    }

    #workspaces button.active:not(.focused) *,
    #workspaces button.active:not(.focused):hover * {
      color: @waybar-accent-2;
    }

    #workspaces button.urgent {
      color: ${wb.urgentFg};
      background: ${wb.urgentBg};
      border-color: transparent;
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

    #custom-quotabar-claude,
    #custom-quotabar-codex {
      background-repeat: no-repeat;
      background-position: 8px center;
      background-size: 14px 14px;
      padding: 0 8px 0 28px;
    }

    window#waybar.compact * {
      font-size: 12px;
    }

    window#waybar.compact #clock,
    window#waybar.compact #battery,
    window#waybar.compact #network,
    window#waybar.compact #wireplumber,
    window#waybar.compact #language,
    window#waybar.compact #custom-caffeine,
    window#waybar.compact #custom-agent-status,
    window#waybar.compact #custom-tray-expander {
      padding: 0 5px;
    }

    window#waybar.compact #tray {
      padding: 0 2px;
    }

    window#waybar.compact #workspaces {
      padding: 1px 2px;
    }

    window#waybar.compact #workspaces button {
      margin: 0;
      padding: 1px 3px;
    }

    window#waybar.compact #custom-quotabar-claude,
    window#waybar.compact #custom-quotabar-codex {
      background-position: 5px center;
      background-size: 11px 11px;
      padding: 0 5px 0 18px;
    }

    /* Icons are written by `quotabar waybar` on first run */
    #custom-quotabar-claude {
      background-image: url("${homeDir}/.local/share/quotabar/claude.svg");
    }

    #custom-quotabar-codex {
      background-image: url("${homeDir}/.local/share/quotabar/openai.svg");
    }

    #custom-quotabar-claude.warning,
    #custom-quotabar-codex.warning {
      color: ${wb.quotaWarning};
    }

    #custom-quotabar-claude.critical,
    #custom-quotabar-codex.critical {
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

    "custom/quotabar-claude" = {
      exec = "${homeDir}/.cargo/bin/quotabar waybar --provider claude";
      return-type = "json";
      interval = 60;
      on-click = "${homeDir}/.cargo/bin/quotabar popup";
    };

    "custom/quotabar-codex" = {
      exec = "${homeDir}/.cargo/bin/quotabar waybar --provider codex";
      return-type = "json";
      interval = 60;
      on-click = "${homeDir}/.cargo/bin/quotabar popup";
    };

    "custom/agent-status" = {
      exec = "${homeDir}/dotfiles/bin/agent-status";
      return-type = "json";
      interval = 2;
      on-click = "${homeDir}/code/agent-switch/target/debug/agent-switch demo-sidebar --live";
    };

    "custom/caffeine" = {
      exec = "${homeDir}/dotfiles/bin/caffeine status";
      return-type = "json";
      interval = "once";
      signal = 8;
      on-click = "${homeDir}/dotfiles/bin/caffeine toggle";
    };
  };

  niriLanguage = {
    format = "{}";
    "format-en" = "AU";
    "format-sv" = "SE";
    "on-click" = "niri msg action switch-layout next";
  };

  hyprlandLanguage = {
    format = "{}";
    "format-en" = "AU";
    "format-sv" = "SE";
    "on-click" = "hyprctl switchxkblayout all next";
  };

  hyprlandWorkspaces = {
    format = "{icon} {id} {name}";
    "format-icons" = {
      main = "󰧨";
      web = "󰖟";
      dotfiles = "󰚩";
      default = "";
    };
    "on-click" = "activate";
  };

  standardNiriBar = sharedModules // {
    layer = "top";
    position = "top";
    height = 26;
    output = [
      "!eDP-1"
      "*"
    ];
    "modules-left" = [ "niri/workspaces" ];
    "modules-center" = [ "niri/window" ];
    "niri/workspaces" = {
      format = "{icon} {index} {name}";
      "format-icons" = {
        main = "󰧨";
        web = "󰖟";
        dotfiles = "󰚩";
        default = "";
      };
    };
    "modules-right" = [
      "custom/agent-status"
      "custom/quotabar-claude"
      "custom/quotabar-codex"
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
        "org.gnome.(.*) - (.*)" = "$1 - $2";
        "firefox - (.*)" = "Firefox - $1";
        "Spotify - (.*)" = "Spotify - $1";
        "slack - (.*)" = "Slack - $1";
        "1password - (.*)" = "1Password - $1";
      };
    };

    "niri/language" = niriLanguage;
  };

  compactNiriBar = sharedModules // {
    layer = "top";
    position = "top";
    height = 24;
    name = "compact";
    output = "eDP-1";
    "modules-left" = [ "niri/workspaces" ];
    "modules-center" = [ ];
    "modules-right" = [
      "custom/agent-status"
      "custom/quotabar-claude"
      "custom/quotabar-codex"
      "custom/caffeine"
      "niri/language"
      "group/tray"
      "network"
      "wireplumber"
      "battery"
      "clock"
    ];

    "group/tray" = {
      orientation = "inherit";
      drawer = {
        "transition-duration" = 200;
        "transition-left-to-right" = false;
        "click-to-reveal" = true;
      };
      modules = [
        "custom/tray-expander"
        "tray#compact"
      ];
    };

    "custom/tray-expander" = {
      format = "⋯";
      tooltip = false;
    };

    "tray#compact" = {
      "icon-size" = 14;
      spacing = 2;
      "show-passive-items" = false;
    };

    "niri/workspaces" = {
      format = "{icon} {index} {name}";
      "format-icons" = {
        main = "󰧨";
        web = "󰖟";
        dotfiles = "󰚩";
        default = "";
      };
    };

    "niri/language" = niriLanguage;

    battery = sharedModules.battery // {
      # A narrow no-break space keeps the compact charging glyph clear of the digits.
      format = "{icon} {capacity}%";
      "format-charging" = "{icon} {capacity}%";
      "format-not-charging" = "{icon} {capacity}%";
      "format-plugged" = "{icon} {capacity}%";
      "format-full" = "󰂅 {capacity}%";
    };
  };

  # Hyprland variants: same bars with hyprland/* modules swapped in.
  swapLanguage = map (m: if m == "niri/language" then "hyprland/language" else m);

  standardHyprlandBar = standardNiriBar // {
    "modules-left" = [ "hyprland/workspaces" ];
    "modules-center" = [ "hyprland/window" ];
    "modules-right" = swapLanguage standardNiriBar."modules-right";
    "hyprland/workspaces" = hyprlandWorkspaces;
    "hyprland/language" = hyprlandLanguage;
    "hyprland/window" = {
      format = "{class} - {title}";
      max-length = 80;
      tooltip = false;
      rewrite = standardNiriBar."niri/window".rewrite;
    };
  };

  compactHyprlandBar = compactNiriBar // {
    "modules-left" = [ "hyprland/workspaces" ];
    "modules-right" = swapLanguage compactNiriBar."modules-right";
    "hyprland/workspaces" = hyprlandWorkspaces;
    "hyprland/language" = hyprlandLanguage;
  };
in
{
  programs.waybar = {
    enable = true;
    # No default config - using Niri-specific config below
    settings = [ ];
    style = sharedStyle;
  };

  # Niri-specific multi-output config: compact on the laptop panel, full elsewhere.
  xdg.configFile."waybar/config-niri".text = builtins.toJSON [
    standardNiriBar
    compactNiriBar
  ];

  xdg.configFile."waybar/style-niri.css".text = sharedStyle;

  # Hyprland-specific config (spawned from config/hypr/lua/autostart.lua).
  xdg.configFile."waybar/config-hyprland".text = builtins.toJSON [
    standardHyprlandBar
    compactHyprlandBar
  ];

  xdg.configFile."waybar/style-hyprland.css".text = sharedStyle;
}
