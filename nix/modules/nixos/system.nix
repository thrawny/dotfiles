{ config, pkgs, lib, ... }:
let
  cfg = config.dotfiles;
  username = cfg.username;
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
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

    # Keyd for system-wide key remapping (works in all apps including Electron)
    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = ["*"];
          settings = {
            main = {
              # Swap Caps Lock and Escape
              capslock = "esc";
              esc = "capslock";

              # Swap Alt and Ctrl for Mac-like layout
              leftalt = "leftcontrol";
              leftcontrol = "leftalt";
              rightalt = "rightcontrol";
              rightcontrol = "rightalt";
            };
            "shift" = {
              "102nd" = "S-grave";  # Shift+< produces Shift+grave which is ~
            };
          };
        };
      };
    };

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      nerd-fonts.caskaydia-mono
    ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = {
      inherit dotfiles username;
      gitIdentity = gitIdentity;
    };

    home-manager.users.${username} = import ../home-manager/default.nix;
  };
}
