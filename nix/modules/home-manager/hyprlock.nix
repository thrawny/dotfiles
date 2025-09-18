{ lib, dotfiles, ... }:
let
  wallpaperPath = "${dotfiles}/config/hypr/wallpaper.png";
  haveWallpaper = builtins.pathExists wallpaperPath;
  backgroundConfig = if haveWallpaper then {
    monitor = "";
    path = wallpaperPath;
  } else {
    monitor = "";
    color = "rgba(0, 0, 0, 0.85)";
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
        inner_color = "rgba(30, 30, 46, 0.65)";
        outer_color = "rgba(137, 180, 250, 0.8)";
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 32;
        rounding = 8;
      };
      label = {
        monitor = "";
        text = "\$FPRINTPROMPT";
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 22;
        valign = "center";
        halign = "center";
        position = "0, -120";
      };
    };
  };
}
