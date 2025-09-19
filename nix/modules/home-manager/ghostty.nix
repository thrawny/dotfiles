{ ... }:
{
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Molokai";
      background = "#1c1c1c";
      foreground = "#F0F0F0";
      font-family = "CaskaydiaMono Nerd Font";
      font-size = 9;
      window-padding-x = 10;
      window-padding-y = 5;
      cursor-style-blink = false;
      font-synthetic-style = false;
      minimum-contrast = 1.2;
      selection-background = "#49483e";
      selection-foreground = "#f8f8f2";
      palette = [
        "0=#5c5c5c"
        "8=#808080"
      ];
    };
  };
}
