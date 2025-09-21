{ ... }:
{
  imports = [
    ../shared/1password.nix
    ./system.nix
    ./hyprland.nix
    ./containers.nix
  ];
}
