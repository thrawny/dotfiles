{
  lib,
  config,
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

  # Lid close: suspend immediately, hibernate after 2 hours
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=2h
  '';

  # Host-specific home-manager overrides
  home-manager.users.${config.dotfiles.username} = {
    programs.ghostty.settings.font-size = 11;

    # Laptop: open windows maximized (small screen)
    programs.niri.settings.window-rules = [
      { open-maximized = true; }
    ];
  };
}
