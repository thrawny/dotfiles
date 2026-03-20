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
    homeSource = "repo";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Lenovo ThinkPad T14 Gen 1
  # Intel Core i5-10310U, 16GB RAM, 256GB NVMe, FHD panel

  # Bootloader: ThinkPad uses systemd-boot via the EFI partition; force-disable GRUB to avoid nix build errors.
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 2;
    };
    efi.canTouchEfiVariables = true;
    grub.enable = lib.mkForce false;
  };

  # Host-specific home-manager overrides
  home-manager.users.${config.dotfiles.username} = {
    programs.ghostty.settings.font-size = 11;

    # Laptop: open windows maximized (small screen)
    programs.niri.settings.window-rules = [
      { open-maximized = true; }
    ];
  };
}
