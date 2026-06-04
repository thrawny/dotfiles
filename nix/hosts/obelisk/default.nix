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
    ../../modules/nixos/tailscale-serve.nix
    ../../modules/nixos/forgejo.nix
    ../../modules/nixos/agents.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  dotfiles = {
    username = "thrawny";
    homeSource = "store";
    fullName = "Jonas Lergell";
    email = "jonas@lergell.se";
    tailnetDomain = "tailf85bba.ts.net";
  };

  users.users.thrawny.hashedPasswordFile = "/etc/user-password";
  users.users.thrawny.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2Uiv/7oVuix/LbkSZw4BamMlo0uRYNtr5bRHHUSL5Y jonas@lergell.se"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2Uiv/7oVuix/LbkSZw4BamMlo0uRYNtr5bRHHUSL5Y jonas@lergell.se"
  ];

  services.openssh.openFirewall = false;

  services.tailscale = {
    authKeyFile = "/etc/tailscale/auth-key";
    extraUpFlags = [
      "--ssh"
      "--advertise-tags=tag:server"
    ];
  };

  services.tailscaleServe.enable = true;

  networking = {
    hostName = "obelisk";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  environment.systemPackages = with pkgs; [
    btop
    ncurses
    (lib.hiPrio ghostty.terminfo)
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  home-manager.users.${username} = {
    imports = [
      ../../home/shared/bash.nix
      ../../home/shared/zsh.nix
      ../../home/shared/git.nix
      ../../home/shared/starship.nix
    ];

    programs.home-manager.enable = true;

    home = {
      stateVersion = "24.05";
      inherit username;
      homeDirectory = "/home/${username}";
      packages = with pkgs; [
        ncurses
        (lib.hiPrio ghostty.terminfo)
      ];
      sessionVariables = {
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        COLORTERM = "truecolor";
      };
    };
  };
}
