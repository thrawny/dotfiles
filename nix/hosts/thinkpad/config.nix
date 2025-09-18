{ lib, ... }:
{
  imports = [
    ../../modules/nixos/default.nix
    ./hardware-configuration.nix
  ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Bootloader: ThinkPad uses systemd-boot via the EFI partition; force-disable GRUB to avoid nix build errors.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = lib.mkForce false;
}
