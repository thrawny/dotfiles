{
  config,
  pkgs,
  lib,
  zen-browser,
  walker,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
  packages = import ../shared/packages.nix {
    inherit pkgs lib;
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
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    users.users.${username} = {
      isNormalUser = true;
      home = userHome;
      extraGroups = [
        "wheel"
        "video"
        "audio"
        "input"
        "keyd" # Access to keyd socket for application-mapper
      ];
      shell = pkgs.zsh;
    };

    # Create keyd group for socket access
    users.groups.keyd = { };

    environment.systemPackages =
      packages.systemPackages
      ++ (with pkgs; [
        nixfmt-rfc-style # Nix formatter (provides nixfmt command)
        nil # Nix Language Server
        nixfmt-tree # Treefmt pre-configured for Nix files
      ]);

    programs = {
      zsh.enable = true;
      direnv.enable = true;

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

      # Keyd for system-wide key remapping (works in all apps including Electron)
      keyd = {
        enable = true;
        keyboards = {
          # ThinkPad built-in keyboard - needs Alt/Win swap
          thinkpad = {
            ids = [ "0001:0001:70533846" ]; # AT Translated Set 2 keyboard exact ID
            settings = {
              main = {
                # Both Caps Lock and Escape produce Escape
                capslock = "esc";
                esc = "esc";

                # Swap Meta (Super/Windows) and Alt keys for Mac-like layout
                leftmeta = "leftalt";
                leftalt = "leftmeta";
                rightalt = "rightmeta";
              };
              "shift" = {
                "102nd" = "S-grave"; # Shift+< produces Shift+grave which is ~
              };
            };
          };

          # Default for all other keyboards (no Alt/Win swap)
          default = {
            ids = [ "*" ]; # Match all keyboards (keyd prioritizes specific matches first)
            settings = {
              main = {
                # Both Caps Lock and Escape produce Escape
                capslock = "esc";
                esc = "esc";

                # Keychron Max5 special buttons (circle, triangle, square, X) -> F9-F12
                f13 = "f9"; # Circle
                f14 = "f10"; # Triangle
                f15 = "f11"; # Square
                f16 = "f12"; # X
              };
              "shift" = {
                "102nd" = "S-grave"; # Shift+< produces Shift+grave which is ~
              };
            };
          };
        };
      };
    };

    # Configure keyd socket permissions for application-mapper access
    systemd.services.keyd.serviceConfig = {
      RuntimeDirectoryMode = "0750";
      UMask = lib.mkForce "0007";
      Group = "keyd";
    };

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.caskaydia-mono
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {
        inherit
          dotfiles
          username
          zen-browser
          walker
          gitIdentity
          ;
      };
      users.${username} = import ../../home/nixos/default.nix;
    };
  };
}
