{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscaleAuthKeyFile = "/etc/tailscale/auth-key";
  atticStorage = {
    # Hetzner Object Storage location codes: fsn1, nbg1, hel1
    region = "hel1";
    bucket = "thrawny-attic-storage";
    endpoint = "https://hel1.your-objectstorage.com";
  };
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

  # Prevent SSH from being open to the entire internet.
  # Access is allowed via Tailscale and the temporary allowlisted IP below.
  services.openssh.openFirewall = false;

  # SSH access
  users.users.thrawny.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];

  networking = {
    hostName = "attic-server";
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
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Use GRUB for Hetzner (legacy BIOS boot)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 2;
  };

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };
    optimise.automatic = true;
    settings = {
      keep-derivations = false;
      keep-outputs = false;
    };
  };

  services.atticd = {
    enable = true;
    environmentFile = "/etc/atticd/atticd.env";
    settings = {
      # Serve over Tailscale-only networking.
      listen = "0.0.0.0:8080";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "s3";
        inherit (atticStorage)
          region
          bucket
          endpoint
          ;
      };
    };
  };

  # Bootstraps Tailscale on first boot if /etc/tailscale/auth-key is provisioned.
  systemd.services.tailscale-autoconnect = {
    description = "Authenticate Tailscale using a provisioned auth key";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    unitConfig.ConditionPathExists = tailscaleAuthKeyFile;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      auth_key="$(tr -d '\n' < ${tailscaleAuthKeyFile})"
      if [ -z "$auth_key" ]; then
        exit 0
      fi

      ${pkgs.tailscale}/bin/tailscale up --auth-key "$auth_key" --ssh
      rm -f ${tailscaleAuthKeyFile}
    '';
  };

  # Ensure secret directories exist for files provisioned by nixos-anywhere --extra-files.
  systemd.tmpfiles.rules = [
    "d /etc/atticd 0700 root root -"
    "d /etc/tailscale 0700 root root -"
  ];

  environment.systemPackages = with pkgs; [
    attic-client
  ];
}
