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
    ../../modules/nixos/headless.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  dotfiles = {
    username = "thrawny";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  # Prevent openssh from auto-opening port 22 to all IPs;
  # SSH is only reachable via Tailscale (trusted) and the allowlisted IP below.
  services.openssh.openFirewall = false;

  # SSH access
  users.users.thrawny.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];

  networking = {
    hostName = "thrawny-server";
    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
      extraCommands = ''
        iptables -I INPUT -p tcp --dport 22 -s 84.216.114.142 -j ACCEPT
      '';
      extraStopCommands = ''
        iptables -D INPUT -p tcp --dport 22 -s 84.216.114.142 -j ACCEPT || true
      '';
    };
  };
  nix.settings.trusted-users = [ username ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Use GRUB for Hetzner (legacy BIOS boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  home-manager.users.${username} = import ../../home/nixos/headless.nix;
}
