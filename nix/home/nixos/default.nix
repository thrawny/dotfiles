# Home Manager config for NixOS desktops
{
  pkgs,
  config,
  lib,
  osConfig,
  username,
  xremap-flake,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # xremap home-manager module (from flake)
    xremap-flake.homeManagerModules.default
    ./xremap.nix

    # Hyprland (default and sole enabled compositor)
    ./hyprland.nix

    # Desktop modules
    ./hypridle.nix
    ./hyprlock.nix
    ./btop.nix
    ./mako.nix
    ./desktop-broker.nix
    ./telegram.nix
    ./walker.nix
    ./waybar.nix
    ./gtk.nix
    ./viewers.nix
    ./voxtype.nix
  ]
  ++ lib.optionals osConfig.programs.niri.enable [
    ./niri
    ./niri/switcher.nix
  ];

  services.wpaperd = {
    enable = true;
    settings.any = {
      path = "${config.home.homeDirectory}/dotfiles/assets";
      sorting = "ascending";
      duration = "1h";
    };
  };

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      swayosd
      vesktop # Discord client with Wayland screen sharing support
    ];
  };
}
