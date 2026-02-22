{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  self,
  xremap-flake,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # xremap home-manager module (from flake)
    xremap-flake.homeManagerModules.default

    # Linux-specific modules
    ../linux

    # Niri window manager (base + switcher, no DMS)
    ../linux/niri
    ../linux/niri/switcher.nix

    # NixOS-specific modules
    ./btop.nix
    ./mako.nix
    ./telegram.nix
    ./walker.nix
    ./waybar.nix
    ./zen-browser.nix
    ./gtk.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      vesktop # Discord client with Wayland screen sharing support
      zathura # PDF viewer with vim keybindings and auto-reload
    ];
  };
}
