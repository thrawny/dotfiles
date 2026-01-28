{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
  gitIdentity =
    let
      inherit (cfg) fullName email;
    in
    {
      name = fullName;
      inherit email;
    };

  basePackages = with pkgs; [
    curl
    git
    neovim
    ripgrep
    tmux
    wget
    unzip
  ];
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
    };

    users.users.${username} = {
      isNormalUser = true;
      home = userHome;
      extraGroups = [
        "wheel"
        "docker"
      ];
      shell = pkgs.zsh;
    };

    environment.systemPackages = basePackages;

    programs = {
      zsh = {
        enable = true;
        enableGlobalCompInit = false; # Home Manager handles compinit
      };
      direnv.enable = true;
    };

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
      tailscale.enable = true;
      xserver.enable = false;
      openssh.enable = true;
      resolved.enable = true;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";
      extraSpecialArgs = {
        inherit
          self
          dotfiles
          username
          gitIdentity
          ;
      };
    };
  };
}
