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
    ./hibernate.nix
  ];

  dotfiles = {
    username = "thrawny";
    homeSource = "repo";
    fullName = "Jonas Lergell";
    email = "jonas@lergell.se";
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=SE
    options thinkpad_acpi fan_control=1 experimental=1
  '';
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Thinkfan: custom fan curve for quieter operation
  services.thinkfan = {
    enable = true;
    sensors = [
      {
        type = "hwmon";
        query = "/sys/class/hwmon";
        name = "k10temp";
        indices = [ 1 ];
      }
      {
        type = "hwmon";
        query = "/sys/class/hwmon";
        name = "amdgpu";
        indices = [ 1 ];
      }
    ];
    fans = [
      {
        type = "tpacpi";
        query = "/proc/acpi/ibm/fan";
      }
    ];
    levels = [
      [
        0
        0
        55
      ]
      [
        1
        48
        60
      ]
      [
        2
        55
        65
      ]
      [
        3
        60
        70
      ]
      [
        4
        65
        75
      ]
      [
        5
        70
        80
      ]
      [
        7
        75
        85
      ]
      [
        "level full-speed"
        85
        32767
      ]
    ];
  };

  # Battery longevity: keep charge between 40-80%.
  # Override temporarily with: sudo tlp fullcharge BAT0
  services.tlp.settings = {
    START_CHARGE_THRESH_BAT0 = 40;
    STOP_CHARGE_THRESH_BAT0 = 80;
  };

  services = {
    # Fingerprint reader (Synaptics on Z13 Gen 2)
    fprintd.enable = true; # sudo/login get fprintAuth automatically

    # ZeroTier VPN
    zerotierone.enable = true;
  };

  users.users.${config.dotfiles.username}.extraGroups = [ "incus-admin" ];

  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.0.100.1/24";
            "ipv4.nat" = "true";
            "ipv6.address" = "none";
          };
        }
      ];
      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              size = "35GiB";
              type = "disk";
            };
          };
        }
      ];
      storage_pools = [
        {
          name = "default";
          driver = "dir";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];
    };
  };

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
  };

  security.pam.services.polkit-1 = {
    fprintAuth = true;
    unixAuth = true;
  }; # 1Password

  networking = {
    hostName = "thrawny-z13";
    nftables.enable = true;
    firewall.trustedInterfaces = [ "incusbr0" ];
  };

  # Host-specific home-manager overrides
  home-manager.users.${config.dotfiles.username} = {
    programs.ghostty.settings.font-size = 11;

    programs.niri.settings = {
      outputs = {
        # Laptop screen - centered below work ultrawide
        "eDP-1" = {
          scale = 1.75;
          position = {
            x = 898;
            y = 1440;
          };
        };
        # Home: LG 27GL850 - middle (main monitor)
        "DP-8" = {
          scale = 1.0;
          position = {
            x = 1646;
            y = 0;
          };
        };
        # Home: AOC Q27G2WG4 - right
        "DP-2" = {
          scale = 1.0;
          mode = {
            width = 2560;
            height = 1440;
            refresh = 143.912;
          };
          position = {
            x = 4206;
            y = 0;
          };
        };
        # Work: Philips 346E2C ultrawide - above laptop
        "DP-1" = {
          scale = 1.0;
          position = {
            x = 0;
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
      pkgs.element-desktop
      pkgs.google-chrome
      pkgs.slack
      pkgs.teams-for-linux
      pkgs.terraform
      pkgs.hcloud
    ];
  };
}
