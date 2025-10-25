{
  config,
  lib,
  ...
}:
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
  services.xserver.videoDrivers = [ "nvidia" ];  # Load NVIDIA driver
  hardware.nvidia = {
    open = false; # Use proprietary drivers for better compatibility
    modesetting.enable = true; # Required for Wayland
    nvidiaSettings = true;
    powerManagement.enable = true; # For suspend/hibernate support
    package = config.boot.kernelPackages.nvidiaPackages.stable;  # Use stable driver
  };

  # Load NVIDIA kernel modules
  boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  # Desktop-specific home-manager overrides
  home-manager.users.thrawny = { lib, ... }:
  let
    baseInputConfig = import ../../home/nixos/hyprland/input-base.nix;
  in
  {
    programs.ghostty.settings.font-size = lib.mkForce 12;

    # Monitor configuration for desktop
    wayland.windowManager.hyprland.settings.monitor = [
      "HDMI-A-1, 2560x1440@99.95, 0x0, 1"      # LG 27GL850 (left)
      "DP-1, 2560x1440@59.95, 2560x0, 1"       # AOC Q27G2WG4 (right)
    ];

    # Override input config with desktop-specific sensitivity
    wayland.windowManager.hyprland.settings.input = lib.mkForce (baseInputConfig // {
      sensitivity = -0.2;  # Desktop-specific sensitivity
    });
  };
}
