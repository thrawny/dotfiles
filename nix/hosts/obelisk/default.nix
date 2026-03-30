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
    ../../modules/nixos/forgejo.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  dotfiles = {
    username = "thrawny";
    homeSource = "store";
    fullName = "Jonas Lergell";
    email = "jonas@lergell.se";
  };

  users.users.thrawny.hashedPasswordFile = "/etc/user-password";

  services.openssh.openFirewall = false;

  services.tailscale = {
    authKeyFile = "/etc/tailscale/auth-key";
    extraUpFlags = [ "--ssh" ];
  };

  networking = {
    hostName = "obelisk";
    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  home-manager.users.${username} = {
    imports = [
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
