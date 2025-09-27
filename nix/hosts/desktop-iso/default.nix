{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    ../desktop/default.nix
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
  ];

  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # Faster compression for development
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  # Auto-login
  services.getty.autologinUser = lib.mkForce "thrawny";

  # Include installer tools
  environment.systemPackages = with pkgs; [
    gparted
    nixos-install-tools
  ];
}