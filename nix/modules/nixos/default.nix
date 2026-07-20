{ ... }:
{
  imports = [
    ./system.nix
    ./desktop.nix
    ./1password.nix
    ./docker.nix
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
