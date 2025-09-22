{ pkgs, ... }:
{
  wayland.windowManager.hyprland.settings.exec-once = [
    "waybar"
    "${pkgs.hyprpaper}/bin/hyprpaper"
  ];
}
