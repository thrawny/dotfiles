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
    ./ghostty.nix
    ./steam.nix
    ./hyprland/default.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./keyd-app-mapper.nix
    ./mako.nix
    ./walker.nix
    ./waybar.nix
    ./zen-browser.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      grimblast # Screenshot tool for Hyprland (grim + slurp wrapper)
      telegram-desktop
    ];
  };
}
