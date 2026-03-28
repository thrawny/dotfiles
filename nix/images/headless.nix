{
  config,
  lib,
  pkgs,
  modulesPath,
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

    ${pkgs.neovim}/bin/nvim --headless '+Lazy! restore' +qa

    touch ${lib.escapeShellArg restoreMarker}
  '';
in
{
  imports = [
    ../modules/nixos/headless.nix
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
  virtualisation.docker.enable = true;

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
      environment.sessionVariables.INCUS_CONTAINER = "incus";
      services.tailscale.enable = lib.mkForce false;
      services.resolved.enable = lib.mkForce false;
      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 1.1.1.1
        nameserver 8.8.8.8
      '';

      system.build.image = lib.mkForce (pkgs.runCommand "headless-incus-image" { } ''
        mkdir -p "$out"
        ln -s ${config.system.build.metadata}/tarball/*.tar.xz "$out/metadata.tar.xz"
        ln -s ${config.system.build.tarball}/tarball/*.tar.xz "$out/rootfs.tar.xz"
      '');
    };
}
