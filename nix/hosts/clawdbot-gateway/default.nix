{
  config,
  lib,
  pkgs,
  nix-clawdbot,
  ...
}:
let
  inherit (config.dotfiles) username;
in
{
  imports = [
    ../../modules/nixos/system.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # Add clawdbot overlay to make pkgs.clawdbot available
  nixpkgs.overlays = [ nix-clawdbot.overlays.default ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
    headless = true;
  };

  # SSH access
  users.users.thrawny.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];

  networking.hostName = "clawdbot-gateway";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Use GRUB for Hetzner (legacy BIOS boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Workaround: nix-clawdbot uses hardcoded /bin paths which don't exist on NixOS
  # TODO: File upstream PR to fix this
  systemd.tmpfiles.rules = [
    "L+ /bin/mkdir - - - - ${pkgs.coreutils}/bin/mkdir"
    "L+ /bin/ln - - - - ${pkgs.coreutils}/bin/ln"
  ];

  # Override home-manager to use headless config (no Wayland/UI modules)
  home-manager.users.${username} = lib.mkForce (
    { nix-clawdbot, ... }:
    {
      imports = [
        ../../home/nixos/headless.nix
        ../../home/nixos/clawdbot-gateway.nix
      ];
    }
  );
}
