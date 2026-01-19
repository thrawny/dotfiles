{
  config,
  pkgs,
  lib,
  self,
  zen-browser,
  walker,
  nurPkgs,
  xremap-flake,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
  packages = import ./packages.nix {
    inherit pkgs lib nurPkgs;
    excludePackages = [ ];
  };
  gitIdentity =
    let
      inherit (cfg) fullName email;
    in
    {
      name = fullName;
      inherit email;
    };
in
{
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

    # Set timezone
    time.timeZone = "Europe/Stockholm";

    nixpkgs.config.allowUnfree = true;

    # Enable flakes and nix command
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Pre-trust niri cache so it works on first build (before niri-flake module applies)
      trusted-substituters = [ "https://niri.cachix.org" ];
      trusted-public-keys = [
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      ];
    };

    users.users.${username} = {
      isNormalUser = true;
      home = userHome;
      extraGroups = [
        "wheel"
        "video"
        "audio"
        "input"
        "docker" # Run Docker without sudo
      ];
      shell = pkgs.zsh;
    };

    environment.systemPackages =
      packages.systemPackages
      ++ (with pkgs; [
        nixfmt-rfc-style # Nix formatter (provides nixfmt command)
        nil # Nix Language Server
        nixfmt-tree # Treefmt pre-configured for Nix files
      ]);

    programs = {
      zsh = {
        enable = true;
        enableGlobalCompInit = false; # We call compinit in ~/.zshrc
      };
      direnv.enable = true;
      niri.enable = true; # uses niri-flake's cached package

      # Enable nix-ld for running non-Nix binaries (e.g., uv run ruff)
      nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc.lib # Basic C/C++ libraries
          zlib # Compression library
          openssl # SSL/TLS
        ];
      };

      # Enable AppImage support
      appimage = {
        enable = true;
        binfmt = true;
      };
    };

    hardware.bluetooth.enable = true;
    networking.networkmanager.enable = true;

    # Allow passwordless nix commands for wheel group
    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nix-collect-garbage";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nix-env";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    services = {
      xserver.enable = false;
      openssh.enable = true;
      pulseaudio.enable = false;
      pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
      };
      greetd = {
        enable = true;
        settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      };
      resolved.enable = true;
      blueman.enable = true;

      # Keyd disabled - using xremap instead to avoid double-grab keyboard conflicts
      # Config preserved in git history if needed later
      keyd.enable = false;
    };

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.caskaydia-mono
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";
      # niri-flake.nixosModules.niri already adds home-manager integration
      extraSpecialArgs = {
        inherit
          self
          dotfiles
          username
          zen-browser
          walker
          gitIdentity
          xremap-flake
          ;
      };
      users.${username} = import ../../home/nixos/default.nix;
    };
  };
}
