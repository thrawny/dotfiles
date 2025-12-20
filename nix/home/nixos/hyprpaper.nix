{
  lib,
  dotfiles,
  ...
}:
let
  wallpaperPath = "${dotfiles}/assets/tokyo.jpg";
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
