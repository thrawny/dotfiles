{ pkgs, theme, ... }:
let
  app = theme.applications.ghostty;
in
{
  programs.ghostty = {
    enable = true;
    # Only install package on Linux (macOS users install via Homebrew or direct download)
    package = if pkgs.stdenv.isLinux then pkgs.ghostty else null;
    settings = {
      inherit (app) theme background foreground;
      font-family = "CaskaydiaMono Nerd Font";
      font-size = 12;
      window-padding-x = 10;
      window-padding-y = 5;
      gtk-titlebar = false;
      gtk-single-instance = true;
      confirm-close-surface = false;
      cursor-style-blink = false;
      font-synthetic-style = false;
      minimum-contrast = 1.2;
      selection-background = app.selectionBackground;
      selection-foreground = app.selectionForeground;
      palette = [
        "0=${app.palette0}"
        "8=${app.palette8}"
      ];
      keybind = [
        "shift+enter=text:\\n"
        "ctrl+enter=unbind"
        "super+a=select_all"
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
      ];
    };
  };
}
