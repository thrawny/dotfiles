{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
  userHome = config.users.users.${username}.home;
  nvimStateDir = "${userHome}/.local/state/nvim";
  restoreMarker = "${nvimStateDir}/restore-complete";
  restoreScript = pkgs.writeShellScript "headless-nvim-restore" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg userHome}
    export USER=${lib.escapeShellArg username}
    export LOGNAME=${lib.escapeShellArg username}
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    export PATH="/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
    export NVIM_HEADLESS=1
    export NVIM_STORE_CONFIG=1

    install -d -m0755 "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${nvimStateDir}"

    ${pkgs.neovim}/bin/nvim --headless -c 'lua require("lazy").restore({ wait = true })' -c 'qa'

    touch ${lib.escapeShellArg restoreMarker}
  '';
in
{
  imports = [
    ../modules/nixos/headless.nix
    ../modules/nixos/docker.nix
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

  nix.settings.sandbox = false;

  systemd.services.headless-nvim-restore = {
    description = "Restore Neovim plugins for the headless image";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "home-manager-${username}.service"
      "network-online.target"
    ];
    after = [
      "home-manager-${username}.service"
      "network-online.target"
    ];
    unitConfig.ConditionPathExists = "!${restoreMarker}";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = restoreScript;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

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
      services.tailscale.enable = lib.mkForce false;
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
