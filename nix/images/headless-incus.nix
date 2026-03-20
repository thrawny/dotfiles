{
  config,
  lib,
  modulesPath,
  ...
}:
{
  home-manager.users.${config.dotfiles.username} = {
    imports = [ ../home/nixos/headless.nix ];
  };

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
}
