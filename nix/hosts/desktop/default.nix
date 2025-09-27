{ config, lib, ... }:
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

  networking.hostName = "thrawny-desktop";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = lib.mkForce false;
  boot.extraModulePackages = with config.boot.kernelPackages; [ rtl8852au ];

  hardware.graphics.enable = true;

  # NVIDIA configuration for dedicated GPU only with Wayland
  hardware.nvidia = {
    open = false;  # Use proprietary drivers for better compatibility
    modesetting.enable = true;  # Required for Wayland
    nvidiaSettings = true;
    powerManagement.enable = true;  # For suspend/hibernate support
  };
}
