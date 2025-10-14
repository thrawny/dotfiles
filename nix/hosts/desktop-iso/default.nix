{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-gnome.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];

  # ISO settings
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  # Faster compression for development (optional - remove for final build)
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  # Include the RTL8852AU WiFi driver
  boot.extraModulePackages = with config.boot.kernelPackages; [ rtl8852au ];

  # Include additional firmware
  hardware.enableRedistributableFirmware = true;

  # Ensure NetworkManager is available
  networking.networkmanager.enable = true;

  # Include some useful tools in the installer
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    pciutils
    usbutils
  ];
}
