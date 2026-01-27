# Standalone Home Manager configuration for MacBook Air running Asahi Linux (Fedora).
# Uses Niri compositor with DankMaterialShell.
#
# Required: Install DankMaterialShell
#   curl -fsSL https://install.danklinux.com | sh
#
# DMS provides: panel, spotlight launcher, lock screen, notifications, wallpaper
{
  lib,
  pkgs,
  username,
  ...
}:
{
  imports = [
    # Cross-platform modules (CLI tools, dotfiles)
    ../../home/shared

    # Linux-specific modules (xremap)
    ../../home/linux

    # Niri with DMS integration
    ../../home/linux/niri
    ../../home/linux/niri/dms.nix
    ../../home/linux/niri/switcher.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";
  };

  # Portal configuration for niri on non-NixOS systems
  # Without this, file dialogs (Save As, Open File) won't work
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.niri.default = [ "gtk" ];
  };

  # Laptop: open windows maximized (small screen)
  programs.niri.settings.window-rules = [
    { open-maximized = true; }
  ];

  # Ghostty overrides for this host
  programs.ghostty = {
    # Use distro packages instead of Nix
    package = lib.mkForce null;
    systemd.enable = lib.mkForce false;
    settings = {
      font-size = 11;
      keybind = [
        "shift+enter=text:\\n"
        "super+a=select_all"
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
      ];
    };
  };
}
