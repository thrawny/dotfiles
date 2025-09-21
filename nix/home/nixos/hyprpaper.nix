{ lib, dotfiles, ... }:
let
  wallpaperPath = "${dotfiles}/config/hypr/wallpaper.png";
  haveWallpaper = builtins.pathExists wallpaperPath;
in
{
  home.file = lib.mkIf haveWallpaper {
    "Pictures/Wallpapers/default.png" = {
      source = wallpaperPath;
      recursive = false;
    };
  };

  services.hyprpaper = lib.mkIf haveWallpaper {
    enable = true;
    settings = {
      preload = [ wallpaperPath ];
      wallpaper = [ ",${wallpaperPath}" ];
    };
  };
}
