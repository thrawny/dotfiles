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

    ${pkgs.neovim}/bin/nvim --headless '+Lazy! restore' +qa

    touch ${lib.escapeShellArg restoreMarker}
  '';
in
{
  imports = [
    ./system.nix
  ];

  users.mutableUsers = lib.mkForce true;

  services.openssh.authorizedKeysFiles = lib.mkForce [
    "/etc/ssh/authorized_keys.d/%u"
    "%h/.ssh/authorized_keys"
  ];

  networking.useDHCP = lib.mkDefault true;

  environment.sessionVariables.INCUS_CONTAINER = "incus";

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 1d";
    };
    optimise.automatic = true;
    settings = {
      keep-derivations = false;
      keep-outputs = false;
    };
  };

  services.tailscale.enable = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

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
}
