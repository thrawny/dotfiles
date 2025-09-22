{ lib, dotfiles, ... }:
let
  wallpaperPath = "${dotfiles}/assets/spacy-bg.png";
in
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ wallpaperPath ];
      wallpaper = [ ",${wallpaperPath}" ];
    };
  };
}
