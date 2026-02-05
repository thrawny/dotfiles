{pkgs, ...}: {
  home.packages = [pkgs.telegram-desktop];

  # Override desktop entry to remove "Quit Telegram" action from launcher
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
