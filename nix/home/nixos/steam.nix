{ pkgs, ... }:
{
  xdg.desktopEntries.steam = {
    name = "Steam";
    comment = "Application for managing and playing games on Steam";
    exec = "steam %U";
    icon = "steam";
    terminal = false;
    type = "Application";
    categories = [
      "Network"
      "FileTransfer"
      "Game"
    ];
    mimeType = [
      "x-scheme-handler/steam"
      "x-scheme-handler/steamlink"
    ];
  };
}
