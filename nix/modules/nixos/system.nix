{ config, pkgs, lib, ... }:
let
  cfg = config.dotfiles;
  username = cfg.username;
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
  theme = {
    palette = {
      background = "#11111b";
      backgroundAlpha = "rgba(17, 17, 27, 0.92)";
      surface = "#1e1e2e";
      border = "#313244";
      text = "#cdd6f4";
      textMuted = "#6c7086";
      accent = "#89b4fa";
      warning = "#f38ba8";
      success = "#a6e3a1";
    };
    fonts = {
      terminal = {
        family = "CaskaydiaMono Nerd Font";
        size = 13;
      };
    };
  };
  packages = import ./packages.nix {
    inherit pkgs lib;
    excludePackages = [ ];
  };
  gitIdentity = {
    name = cfg.fullName;
    email = cfg.email;
  };
in {
  options.dotfiles = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "jonas";
      description = "Unix username for the primary dotfiles-managed account.";
    };

    fullName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Full name to render in ~/.gitconfig.local (optional).";
    };

    email = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email to render in ~/.gitconfig.local (optional).";
    };
  };

  config = {
    networking.hostName = lib.mkDefault "nixos";
    system.stateVersion = "25.11";

    nixpkgs.config.allowUnfree = true;

    services.xserver.enable = false;

    users.users.${username} = {
      isNormalUser = true;
      home = userHome;
      extraGroups = [ "wheel" "video" "audio" "input" ];
      shell = pkgs.zsh;
    };

    programs.zsh.enable = true;
    services.openssh.enable = true;

    services.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
    };

    services.greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
    };

    environment.systemPackages = packages.systemPackages;
    programs.direnv.enable = true;

    services.resolved.enable = true;
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;
    networking.networkmanager.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      nerd-fonts.caskaydia-mono
    ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = {
      inherit dotfiles username theme;
      gitIdentity = gitIdentity;
    };

    home-manager.users.${username} = import ../home-manager/default.nix;
  };
}
