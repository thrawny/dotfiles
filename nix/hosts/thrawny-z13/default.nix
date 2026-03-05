{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/nixos/default.nix
    ../../modules/nixos/laptop.nix
    ./hardware-configuration.nix
  ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonas@lergell.se";
  };

  networking.hostName = "thrawny-z13";
  boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=SE";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ThinkPads use UEFI/systemd-boot.
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
      };
      efi.canTouchEfiVariables = true;
      grub.enable = lib.mkForce false;
    };
    resumeDevice = "/dev/mapper/luks-4d3e8b23-c336-4111-9c1c-ee5ec021e465";
    kernelParams = [ "resume_offset=351778816" ];
  };

  # Swapfile for hibernate (must be >= RAM size)
  swapDevices = [
    {
      device = "/swapfile";
      size = 65536; # 64 GiB
    }
  ];

  # Fingerprint reader (Synaptics on Z13 Gen 2)
  services.fprintd.enable = true; # sudo/login get fprintAuth automatically
  security.pam.services.polkit-1 = {
    fprintAuth = true;
    unixAuth = false; # fingerprint only, no user password
  }; # 1Password

  # Lid close: suspend immediately, hibernate after 2 hours
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  # Host-specific home-manager overrides
  home-manager.users.${config.dotfiles.username} = {
    programs.ghostty.settings.font-size = 11;

    programs.niri.settings = {
      outputs = {
        # Laptop screen - leftmost
        "eDP-1" = {
          scale = 1.75;
          position = {
            x = 0;
            y = 0;
          };
        };
        # LG 27GL850 - middle (main monitor)
        "DP-8" = {
          scale = 1.0;
          position = {
            x = 1646;
            y = 0;
          };
        };
        # AOC Q27G2WG4 - right
        "DP-2" = {
          scale = 1.0;
          position = {
            x = 4206;
            y = 0;
          };
        };
      };
      workspaces = {
        "1-main".open-on-output = "DP-8";
        "2-web".open-on-output = "DP-2";
        "3-dotfiles".open-on-output = "DP-8";
      };
    };

    home.packages = [
      pkgs.google-chrome
      pkgs.slack
      pkgs.teams-for-linux
    ];
  };
}
