{ lib, ... }:
{
  imports = [
    ../../modules/nixos/default.nix
    ./hardware-configuration.nix
  ];

  dotfiles = {
    username = "jonas";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
