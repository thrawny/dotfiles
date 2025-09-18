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

  networking.hostName = "tester";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
}
