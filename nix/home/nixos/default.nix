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
    ./cursor.nix
    ./ghostty.nix
    ./steam.nix
    ./hyprland/default.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    # ./keyd-app-mapper.nix  # DISABLED: Using xremap instead
    ./mako.nix
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
      grimblast # Screenshot tool for Hyprland (grim + slurp wrapper)
      telegram-desktop
      vesktop # Discord client with Wayland screen sharing support
      zathura # PDF viewer with vim keybindings and auto-reload
    ];
  };

  # Override Telegram desktop entry to remove "Quit Telegram" action from launcher
  xdg.desktopEntries."org.telegram.desktop" = {
    name = "Telegram";
    comment = "New era of messaging";
    exec = "Telegram -- %U";
    icon = "org.telegram.desktop";
    terminal = false;
    type = "Application";
    categories = [
      "Chat"
      "Network"
      "InstantMessaging"
      "Qt"
    ];
    mimeType = [
      "x-scheme-handler/tg"
      "x-scheme-handler/tonsite"
    ];
    startupNotify = true;
    settings = {
      StartupWMClass = "TelegramDesktop";
      Keywords = "tg;chat;im;messaging;messenger;sms;tdesktop;";
      DBusActivatable = "true";
      SingleMainWindow = "true";
      X-GNOME-UsesNotifications = "true";
      X-GNOME-SingleWindow = "true";
    };
  };
}
