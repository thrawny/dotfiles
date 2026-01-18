{
  lib,
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

  # Don't auto-start as systemd service - Hyprland's exec-once handles it
  # This prevents crashes when running niri or other compositors
  systemd.user.services.hyprpaper.Install.WantedBy = lib.mkForce [ ];
}
