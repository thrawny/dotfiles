{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./autostart.nix
    ./bindings.nix
    ./envs.nix
    ./input.nix
    ./looknfeel.nix
    ./monitors.nix
    ./windows.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    settings."$mod" = "ALT";
  };
}
