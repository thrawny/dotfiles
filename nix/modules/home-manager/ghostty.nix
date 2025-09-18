{ theme, ... }:
let
  fonts = (theme.fonts or {}).terminal or {
    family = "CaskaydiaMono Nerd Font";
    size = 13;
  };
in
{
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Molokai";
      background = "#1c1c1c";
      foreground = "#F0F0F0";
      "font-family" = fonts.family;
      "font-size" = fonts.size;
      "window-padding-x" = 10;
      "window-padding-y" = 5;
      "cursor-style-blink" = false;
      "font-synthetic-style" = false;
      "minimum-contrast" = 1.2;
      "selection-background" = "#49483e";
      "selection-foreground" = "#f8f8f2";
      palette = [
        "0=#5c5c5c"
        "8=#808080"
      ];
      keybind = [
        "shift+enter=text:\\n\\r"
      ];
    };
  };
}
