{
  config,
  lib,
  pkgs,
  nurPkgs,
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

  # Auto-login on desktop (first boot only, then falls back to tuigreet)
  services.greetd.settings.initial_session = {
    command = "${pkgs.hyprland}/bin/Hyprland";
    user = "thrawny";
  };

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 6;
      };
      efi.canTouchEfiVariables = true;
      grub.enable = lib.mkForce false;
    };

    kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
  };

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
    mangohud # Gaming performance overlay (FPS, temps, etc.)
    nvtopPackages.nvidia # GPU monitoring (htop for NVIDIA GPU)
    pkgsi686Linux.gperftools # 32-bit tcmalloc for Source engine games (HL2, TF2, etc.)
    nurPkgs.repos.Ev357.helium # Helium browser
  ];

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
