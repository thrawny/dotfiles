# Hyprland uses mutable Lua config; edits reload without a NixOS switch.
# hyprlock.conf remains Home Manager generated in hyprlock.nix.
{
  config,
  dotfiles,
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.cliphist
    pkgs.hyprshot
    pkgs.quickshell
  ];

  # Started by Hyprland, not Niri; stopped when the graphical session ends.
  systemd.user.services.dotfiles-shell = {
    Unit = {
      Description = "Dotfiles Quickshell desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c dotfiles";
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

  home.file = {
    ".config/quickshell/dotfiles".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/shell";
    ".config/hypr/hyprland.lua".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/hyprland.lua";
    ".config/hypr/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/lua";
  };
}
