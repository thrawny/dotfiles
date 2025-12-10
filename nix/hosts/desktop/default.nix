{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
in
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

  # Auto-login on desktop (skip tuigreet)
  services.greetd.settings.default_session = {
    command = lib.mkForce "${pkgs.hyprland}/bin/Hyprland";
    user = "thrawny";
  };

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
      grub.enable = lib.mkForce false;
    };

    # DRIVER LAYER: TP-Link Archer TX20U (rtl8852au) WiFi adapter
    extraModulePackages = with config.boot.kernelPackages; [ rtl8852au ];

    # Blacklist conflicting kernel modules that may interfere with rtl8852au
    blacklistedKernelModules = [
      "rtw89_8852au"
      "rtw89_8852a"
      "rtw89_pci"
    ];

    # Force power management off for the 8852au driver
    extraModprobeConfig = ''
      options 8852au rtw_power_mgnt=0 rtw_enusbss=0
    '';

    # KERNEL LAYER: Prevent global USB autosuspend
    kernelParams = [ "usbcore.autosuspend=-1" ];

    kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
  };

  # Disable USB autosuspend for TP-Link Archer TX20U WiFi adapter
  # Fixes issue where dongle is dead on boot and requires Windows reboot to wake
  services.udev.extraRules = ''
    # TP-Link Archer TX20U (2357:013f) - disable autosuspend
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2357", ATTR{idProduct}=="013f", ATTR{power/control}="on"
  '';

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Required for Steam and most games
  };

  # Games partition (~250GB on sdb4)
  fileSystems."/home/${username}/Games" = {
    device = "/dev/disk/by-label/games";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
    ];
  };

  # Desktop-specific packages
  environment.systemPackages = with pkgs; [
    usbutils # USB utilities (includes usbreset for WiFi dongle reset service)
    mangohud # Gaming performance overlay (FPS, temps, etc.)
    nvtopPackages.nvidia # GPU monitoring (htop for NVIDIA GPU)
    pkgsi686Linux.gperftools # 32-bit tcmalloc for Source engine games (HL2, TF2, etc.)
  ];

  # SYSTEMD RESET LAYER: "Nuclear" fix for WiFi dongle
  # Performs USB reset on boot to wake up dongle from firmware hang state
  systemd.services.reset-wifi-dongle = {
    description = "Reset TP-Link Archer TX20U WiFi dongle on boot";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.usbutils}/bin/usbreset 2357:013f";
      RemainAfterExit = true;
    };
  };

  # NVIDIA configuration for dedicated GPU only with Wayland
  services.xserver.videoDrivers = [ "nvidia" ]; # Load NVIDIA driver
  hardware.nvidia = {
    open = false; # Use proprietary drivers for better compatibility
    modesetting.enable = true; # Required for Wayland
    nvidiaSettings = true;
    powerManagement.enable = true; # For suspend/hibernate support
    package = config.boot.kernelPackages.nvidiaPackages.stable; # Use stable driver
  };

  # Gaming configuration
  programs = {
    # Steam
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin # Better game compatibility than default Proton
      ];
      package = pkgs.steam.override {
        extraEnv = {
          GTK_THEME = "Adwaita:dark";
        };
      };
    };

    # GameMode - automatic performance optimizations when gaming
    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10;
          softrealtime = "auto";
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          nv_powermizer_mode = 1; # Max performance mode for NVIDIA
        };
      };
    };

    # Gamescope - compositor for resolution scaling and frame limiting
    gamescope = {
      enable = true;
      capSysNice = true;
    };
  };

  # Desktop-specific home-manager overrides
  home-manager.users.thrawny =
    { lib, ... }:
    let
      baseInputConfig = import ../../home/nixos/hyprland/input-base.nix;
    in
    {
      programs.ghostty.settings.font-size = lib.mkForce 12;

      # Monitor configuration for desktop
      wayland.windowManager.hyprland.settings.monitor = [
        "HDMI-A-1, 2560x1440@99.95, 0x0, 1" # LG 27GL850 (left)
        "DP-1, 2560x1440@59.95, 2560x0, 1" # AOC Q27G2WG4 (right)
      ];

      # Override input config with desktop-specific sensitivity
      wayland.windowManager.hyprland.settings.input = lib.mkForce (
        baseInputConfig
        // {
          sensitivity = -0.2; # Desktop-specific sensitivity
        }
      );
    };
}
