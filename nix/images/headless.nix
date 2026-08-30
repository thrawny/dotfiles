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
    ../modules/headless.nix
  ];

  home-manager.users.${username} = {
    imports = [ ../home/nixos/headless.nix ];
  };

  dotfiles = {
    username = "thrawny";
    homeSource = "store";
  };

  networking.hostName = "headless";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  fonts.fontconfig.enable = true;
  fonts.packages = [ pkgs.dejavu_fonts ];

  nix.settings.sandbox = false;

  # Custom Incus image variant: LXC rootfs + metadata + container-specific config
  image.modules.incus =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/virtualisation/lxc-container.nix")
        (modulesPath + "/virtualisation/lxc-image-metadata.nix")
      ];

      networking.useDHCP = lib.mkDefault true;
      networking.resolvconf.enable = lib.mkForce false;
      services.tailscale.enable = lib.mkForce true;
      services.resolved.enable = lib.mkForce false;
      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 1.1.1.1
        nameserver 8.8.8.8
      '';

      system.build.tarball = lib.mkForce (
        pkgs.callPackage (modulesPath + "/../lib/make-system-tarball.nix") {
          fileName = config.image.baseName;
          extraArgs = "--owner=0";
          storeContents = [
            {
              object = config.system.build.toplevel;
              symlink = "none";
            }
          ];
          contents = [
            {
              source = config.system.build.toplevel + "/init";
              target = "/sbin/init";
            }
            {
              source = config.system.build.toplevel + "/etc/os-release";
              target = "/etc/os-release";
            }
          ];
          extraCommands = "mkdir -p proc sys dev";
          compressCommand = "zstd -T0 -3";
          compressionExtension = ".zst";
          extraInputs = [ pkgs.zstd ];
        }
      );

      system.build.image = lib.mkForce (
        pkgs.runCommand "headless-incus-image" { } ''
          mkdir -p "$out"
          ln -s ${config.system.build.metadata}/tarball/*.tar.xz "$out/metadata.tar.xz"
          ln -s ${config.system.build.tarball}/tarball/*.tar.zst "$out/rootfs.tar.zst"
        ''
      );
    };
}
