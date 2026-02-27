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
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "z13";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ThinkPads use UEFI/systemd-boot.
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 2;
    };
    efi.canTouchEfiVariables = true;
    grub.enable = lib.mkForce false;
  };

  # Z13 G2 includes WWAN hardware in your configuration.
  networking.modemmanager.enable = true;

  # Host-specific home-manager overrides
  home-manager.users.${config.dotfiles.username} = {
    programs.ghostty.settings.font-size = 11;

    # Laptop: open windows maximized (small screen)
    programs.niri.settings.window-rules = [
      { open-maximized = true; }
    ];
  };
}
