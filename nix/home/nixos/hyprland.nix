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

  services.hyprpolkitagent.enable = true;
  # Niri supplies its own agent; UWSM exports this before starting the session.
  systemd.user.services.hyprpolkitagent.Unit.ConditionEnvironment = "XDG_CURRENT_DESKTOP=Hyprland";

  # Started by Hyprland, not Niri; stopped when the graphical session ends.
  systemd.user.services.dotfiles-shell = {
    Unit = {
      Description = "Dotfiles Quickshell desktop shell";
      PartOf = [ "graphical-session.target" ];
      Wants = [
        "dotfiles-agent-switch.service"
        "dotfiles-keepawake.service"
        "shell-clipboard-text.service"
        "shell-clipboard-image.service"
      ];
      After = [
        "graphical-session.target"
        "dotfiles-agent-switch.service"
        "dotfiles-keepawake.service"
      ];
    };
    Service = {
      # Quickshell selects its network backend once. During a switch it can
      # otherwise start before NetworkManager returns and stay offline forever.
      # Wait for daemon startup, not connectivity, so offline sessions still work.
      ExecStartPre = "${pkgs.networkmanager}/bin/nm-online --quiet --wait-for-startup --timeout=30";
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c dotfiles";
      # Apps launched with execDetached must survive shell restarts.
      KillMode = "process";
      # Systemd does not inherit home.sessionPath. The project picker calls
      # hyprland-project from the mutable checkout, not the package profile.
      Environment = "PATH=${
        pkgs.lib.makeBinPath [
          agentSwitchPackage
          quotabarPackage
          clipboardImagePackage
        ]
      }:${dotfiles}/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
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

  home.file = {
    ".config/quickshell/dotfiles".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/shell";
    ".config/hypr/hyprland.lua".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/hyprland.lua";
    ".config/hypr/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/lua";
  };
}
