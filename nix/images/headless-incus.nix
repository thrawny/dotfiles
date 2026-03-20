{
  config,
  lib,
  modulesPath,
  ...
}:
let
  inherit (config.dotfiles) username;
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
  ];
in
{
  imports = [
    (modulesPath + "/virtualisation/lxc-container.nix")
    ../modules/nixos/headless-container.nix
  ];

  dotfiles = {
    username = "thrawny";
    homeSource = "store";
    fullName = "Jonas Lergell";
    email = "jonaslergell@gmail.com";
  };

  networking.hostName = "headless-incus";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  users.users.thrawny.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  home-manager.users.${username} = {
    imports = [ ../home/nixos/headless.nix ];
  };
}
