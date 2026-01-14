# Standalone Home Manager configuration for non-NixOS Linux systems using Niri.
# Expects DankMaterialShell installed on the distro:
#   curl -fsSL https://install.danklinux.com | sh
#
# DMS provides: panel, launcher, lock screen, notifications, wallpaper
{
  config,
  lib,
  pkgs,
  dotfiles,
  self,
  ...
}:
{
  imports = [
    # Shared cross-platform modules (CLI tools, dotfiles)
    ../shared

    # Linux-specific modules
    ../linux/xremap.nix
  ];

  # Portal configuration for niri on non-NixOS systems
  # Without this, file dialogs (Save As, Open File) won't work because
  # xdg-desktop-portal doesn't know which backend to use for niri
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.niri.default = [ "gtk" ];
  };

  # Niri with DMS (DankMaterialShell) integration
  custom.niri = {
    enable = true;
    enableDms = true;
    enableSwitcher = true;
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
      # Font size for this host's display
      font-size = 11;
      # Linux keybindings (Super for copy/paste like macOS Cmd)
      keybind = [
        "shift+enter=text:\\n"
        "super+a=select_all"
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
      ];
    };
  };

  # XWayland satellite for X11 app support
  systemd.user.services.xwayland-satellite = {
    Unit = {
      Description = "XWayland outside your Wayland";
      BindsTo = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      StandardOutput = "journal";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
