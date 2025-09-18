{ lib, dotfiles, theme, ... }:
let
  wallpaperPath = "${dotfiles}/config/hypr/wallpaper.png";
  haveWallpaper = builtins.pathExists wallpaperPath;
  palette = theme.palette;
  backgroundConfig =
    if haveWallpaper then {
      monitor = "";
      path = wallpaperPath;
    } else {
      monitor = "";
      color = palette.background;
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
        inner_color = palette.surface;
        outer_color = palette.accent;
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 32;
        font_color = palette.text;
        placeholder_color = palette.textMuted;
        rounding = 8;
        shadow_passes = 0;
        fade_on_empty = false;
      };
      label = {
        monitor = "";
        text = "\$FPRINTPROMPT";
        font_family = "CaskaydiaMono Nerd Font";
        font_size = 22;
        color = palette.accent;
        valign = "center";
        halign = "center";
        position = "0, -120";
      };
    };
  };
}
