{
  dotfiles,
  ...
}:
let
  wallpapers = [
    "${dotfiles}/assets/tokyo.jpg"
    "${dotfiles}/assets/nasa.jpg"
  ];
in
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = wallpapers;
      wallpaper = [ ",${builtins.head wallpapers}" ];
    };
  };
}
