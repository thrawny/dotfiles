{
  config,
  lib,
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
    homeSource = "store";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  # Prevent openssh from auto-opening port 22 to all IPs;
  # SSH is only reachable via Tailscale (trusted) and the allowlisted IP below.
  services.openssh = {
    openFirewall = false;
    # Listen on 2222 so OpenSSH is reachable alongside Tailscale SSH,
    # which intercepts port 22 on the Tailscale IP.
    ports = [ 2222 ];

  };

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
      extraInputRules = ''
        tcp dport 2222 ip saddr 84.216.114.142 accept
      '';
    };
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Use GRUB for Hetzner (legacy BIOS boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  home-manager.users.${username} = {
    imports = [
      ../../home/nixos/headless.nix
    ];
  };
}
