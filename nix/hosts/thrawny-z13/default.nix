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

  services = {
    # temp ssh
    openssh = {
      enable = true;
      openFirewall = true;
      ports = [ 2222 ];
      settings = {
        PubkeyAuthentication = true;
        AuthenticationMethods = "publickey";
        AuthorizedKeysFile = ".ssh/authorized_keys";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Fingerprint reader (Synaptics on Z13 Gen 2)
    fprintd.enable = true; # sudo/login get fprintAuth automatically

    # ZeroTier VPN
    zerotierone.enable = true;

    # Lid close: suspend immediately, hibernate after 2 hours
    logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
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

  security.pam.services.polkit-1 = {
    fprintAuth = true;
    unixAuth = true;
  }; # 1Password

  # mt7921e WiFi fails to restore from D3cold during hibernate (kernel bug #217415).
  # Unload the driver before sleep and reload after resume as a workaround.
  powerManagement = {
    powerDownCommands = ''
      ${pkgs.kmod}/bin/rmmod mt7921e || true
    '';
    resumeCommands = ''
      ${pkgs.kmod}/bin/modprobe mt7921e
    '';
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

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
      pkgs.google-chrome
      pkgs.slack
      pkgs.teams-for-linux
    ];
  };
}
