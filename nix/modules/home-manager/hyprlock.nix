{ lib, dotfiles, ... }:
let
  wallpaperPath = "${dotfiles}/config/hypr/wallpaper.png";
  haveWallpaper = builtins.pathExists wallpaperPath;
  backgroundConfig =
    if haveWallpaper then {
      monitor = "";
      path = wallpaperPath;
    } else {
      monitor = "";
      color = "#1c1c1c";  # Molokai background
    };
in
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general.disable_loading_bar = true;
      background = backgroundConfig;
      input-field = {
        monitor = "";
        position = "0, 0";
        size = "600, 100";
        halign = "center";
        valign = "center";
        inner_color = "#3a3a3a";  # Molokai surface
        outer_color = "#66d9ef";  # Molokai accent (cyan)
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 32;
        font_color = "#f0f0f0";  # Molokai text
        placeholder_color = "#808080";  # Molokai text muted
        rounding = 8;
        shadow_passes = 0;
        fade_on_empty = false;
      };
      label = {
        monitor = "";
        text = "\$FPRINTPROMPT";
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 22;
        color = "#66d9ef";  # Molokai accent (cyan)
        valign = "center";
        halign = "center";
        position = "0, -120";
      };
    };
  };
}
