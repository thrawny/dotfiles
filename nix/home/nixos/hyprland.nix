# Hyprland uses mutable Lua config; edits reload without a NixOS switch.
# hyprlock.conf remains Home Manager generated in hyprlock.nix.
{
  config,
  dotfiles,
  pkgs,
  quotabar,
  agent-switch,
  ...
}:
let
  agentSwitchPackage = pkgs.callPackage ../../packages/agent-switch.nix { src = agent-switch; };
  quotabarPackage = quotabar.packages.${pkgs.stdenv.hostPlatform.system}.default;
  clipboardImagePackage = pkgs.callPackage ../../packages/shell-clipboard-image.nix { };
in
{
  home.packages = [
    pkgs.cliphist
    pkgs.hyprshot
    pkgs.quickshell
    agentSwitchPackage
    quotabarPackage
    clipboardImagePackage
  ];

  # Started by Hyprland, not Niri; stopped when the graphical session ends.
  systemd.user.services.dotfiles-shell = {
    Unit = {
      Description = "Dotfiles Quickshell desktop shell";
      PartOf = [ "graphical-session.target" ];
      Wants = [
        "dotfiles-agent-switch.service"
        "shell-clipboard-text.service"
        "shell-clipboard-image.service"
      ];
      After = [
        "graphical-session.target"
        "dotfiles-agent-switch.service"
      ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c dotfiles";
      Environment = "PATH=${
        pkgs.lib.makeBinPath [
          agentSwitchPackage
          quotabarPackage
          clipboardImagePackage
        ]
      }:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services.dotfiles-agent-switch = {
    Unit = {
      Description = "Agent tracking and sidebar state";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${agentSwitchPackage}/bin/agent-switch serve --sidebar";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services.shell-clipboard-text = {
    Unit = {
      Description = "Record text clipboard history";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
    };
  };

  systemd.user.services.shell-clipboard-image = {
    Unit = {
      Description = "Record image clipboard history";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
    };
  };

  # Keep caffeine independent of QML hot reloads, but release it at logout.
  systemd.user.services.dotfiles-caffeine = {
    Unit = {
      Description = "Keep the desktop awake while caffeine is enabled";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "exec";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=idle --mode=block --who=dotfiles-caffeine --why=Caffeine ${pkgs.coreutils}/bin/sleep infinity";
    };
  };

  home.file = {
    ".config/quickshell/dotfiles".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/shell";
    ".config/hypr/hyprland.lua".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/hyprland.lua";
    ".config/hypr/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/lua";
  };
}
