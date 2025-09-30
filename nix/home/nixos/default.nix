{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # NixOS-specific modules
    ./cursor.nix
    ./hyprland/default.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./mako.nix
    ./walker.nix
    ./waybar.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";
}