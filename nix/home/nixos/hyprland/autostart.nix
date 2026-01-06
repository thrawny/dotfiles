{ pkgs, config, ... }:
{
  wayland.windowManager.hyprland.settings.exec-once = [
    "waybar -c ${config.home.homeDirectory}/.config/waybar/config -s ${config.home.homeDirectory}/.config/waybar/style.css"
    "${pkgs.hyprpaper}/bin/hyprpaper"
    "${pkgs.ghostty}/bin/ghostty"
    "zen"
  ];
}
