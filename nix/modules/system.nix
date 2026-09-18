{
  config,
  pkgs,
  lib,
  self,
  options,
  ...
}:
let
  cfg = config.dotfiles;
  caches = import ../lib/nix-caches.nix;
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
    ripgrep
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

    homeSource = lib.mkOption {
      type = lib.types.enum [
        "repo"
        "store"
      ];
      default = "repo";
      description = "Where Home Manager should source dotfiles-managed home files from.";
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

    tailnetDomain = lib.mkOption {
      type = lib.types.str;
      default = "tailf85bba.ts.net";
      description = "MagicDNS tailnet domain used for Tailscale Services.";
    };
  };

  config = {
    networking.hostName = lib.mkDefault "nixos";
    system.stateVersion = "25.11";

    # Set timezone
    time.timeZone = "Europe/Stockholm";

    nixpkgs.config.allowUnfree = true;

    nix.settings = {
      trusted-users = lib.mkForce [ "root" ];
      extra-substituters = caches.substituters;
      extra-trusted-public-keys = caches.trustedPublicKeys;
    };

    users.users.${username} = {
      isNormalUser = true;
      home = userHome;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
    };

    environment.systemPackages = basePackages;

    programs = {
      bash.promptInit = "";

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
          glib
          nspr
          nss
          atk
          at-spi2-atk
          dbus
          expat
          at-spi2-core
          libx11
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libgbm
          libxcb
          libxkbcommon
          alsa-lib
        ];
      };
    };

    security.sudo = {
      # Required for the user-specific rule below; sudoers still denies users
      # without an explicit rule.
      execWheelOnly = lib.mkForce false;

      # Deliberately allow the primary user and local agents to rebuild NixOS
      # and recover disk space without an interactive authentication prompt.
      extraRules = [
        {
          users = [ username ];
          commands = [
            {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    services = {
      tailscale.enable = true;
      xserver.enable = false;
      resolved.enable = true;
    };
  }
  // lib.optionalAttrs (builtins.hasAttr "home-manager" options) {
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
        inherit (cfg) homeSource;
      };
    };
  };
}
