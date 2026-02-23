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
    fd
    git
    gnumake
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

    nix.settings = {
      trusted-users = [ username ];
      extra-substituters = [
        "https://cache.numtide.com"
        "https://claude-code.cachix.org"
      ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
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
      # Enable nix-ld for running non-Nix binaries
      nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          openssl
        ];
      };
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
