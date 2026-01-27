{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
in
{
  imports = [
    ../../modules/nixos/system.nix
    ./disko.nix
  ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "clawdbot-gateway";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Use GRUB for Hetzner (legacy BIOS boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Headless - disable desktop services
  services.greetd.enable = lib.mkForce false;
  programs.niri.enable = lib.mkForce false;

  # Override home-manager to use headless config (no Wayland/UI modules)
  home-manager.users.${username} = lib.mkForce (import ../../home/nixos/headless.nix);
}
