{ ... }:
{
  imports = [
    ./system.nix
  ];

  services.openssh.enable = true;
}
