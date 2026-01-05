{ ... }:
{
  imports = [
    ../shared/1password.nix
    ./system.nix
    ./hyprland.nix
    ./niri.nix
    ./containers.nix
  ];
}
