{ ... }:
{
  imports = [
    ./system.nix
    ./desktop.nix
    ./1password.nix
    ./podman.nix
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
