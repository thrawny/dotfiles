{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  self,
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

  # Enable niri compositor config (system-level niri from pkgs.niri)
  custom.niri = {
    enable = true;
    enableSwitcher = true;
  };

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      grimblast # Screenshot tool for Hyprland (grim + slurp wrapper)
      telegram-desktop
      vesktop # Discord client with Wayland screen sharing support
      zathura # PDF viewer with vim keybindings and auto-reload
      self.packages.${pkgs.stdenv.hostPlatform.system}.hyprvoice
    ];
  };

  # Voice-to-text daemon
  systemd.user.services.hyprvoice = {
    Unit = {
      Description = "Voice-to-text for Wayland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${self.packages.${pkgs.stdenv.hostPlatform.system}.hyprvoice}/bin/hyprvoice serve";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
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
