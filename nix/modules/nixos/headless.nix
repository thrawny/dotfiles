{ ... }:
{
  imports = [
    ./system.nix
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
}
