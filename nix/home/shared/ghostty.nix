{
  lib,
  pkgs,
  theme,
  ...
}:
let
  app = theme.applications.ghostty;
  digits = lib.genList (i: toString (i + 1)) 9;
  # Ghostty binds each number twice, logically (super+1) and by physical key
  # (super+digit_1). Unbinding only the logical trigger leaves cmd+1 switching
  # Ghostty tabs, so both have to go for Herdr to see the key.
  unbindDigits = lib.concatMap (d: [
    "super+${d}=unbind"
    "super+digit_${d}=unbind"
  ]) digits;
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
        "ctrl+enter=unbind"
        "ctrl+shift+j=unbind"
        "super+shift+j=unbind"
      ]
      # Let Herdr handle agent selection and navigation on macOS too.
      ++ unbindDigits
      ++ [
        # Ghostty's own super+j (scroll_to_selection) and super+k (clear_screen)
        # would otherwise swallow Herdr's next/previous agent bindings.
        "super+j=unbind"
        "super+k=unbind"
        # Herdr takes super+enter for split_vertical, super+shift+enter for
        # new_tab and super+w for close_tab. Ghostty's toggle_fullscreen,
        # close_surface and close_window go unreplaced: the window manager owns
        # fullscreen, and super+q already quits.
        "super+enter=unbind"
        "super+shift+w=unbind"
        "super+w=unbind"
        # super+d (new_split) is freed for other apps; Herdr splits live on
        # super+enter and the prefix.
        "super+d=unbind"
        "super+a=select_all"
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
      ];
    };
  };
}
