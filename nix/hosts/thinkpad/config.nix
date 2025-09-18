{ lib, ... }:
{
  imports = [
    ../../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
