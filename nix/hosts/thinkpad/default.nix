{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/nixos/default.nix
    ./hardware-configuration.nix
  ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "thinkpad";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

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
