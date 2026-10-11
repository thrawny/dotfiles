{ lib, ... }:
let
  host = import ./default.nix;
in
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = host.username;
  networking.hostName = "thrawnym1";
  networking.localHostName = "thrawnym1";
  users.users.${host.username}.home = "/Users/${host.username}";

  # Determinate continues to own the Nix daemon and nix.conf.
  nix.enable = false;
  programs.zsh.enable = true;

  services.tailscale.enable = true;
  launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

  # tailscaled writes this resolver itself and refuses the store-backed symlink.
  environment.etc."resolver/ts.net".enable = false;
  system.activationScripts.etc.text = lib.mkAfter ''
    if [ ! -e /etc/resolver/ts.net ]; then
      mkdir -p /etc/resolver
      printf 'nameserver 100.100.100.100\n' > /etc/resolver/ts.net
      chmod 644 /etc/resolver/ts.net
    fi
  '';

  # Keep remote access available on AC without changing battery sleep settings.
  # Lid-close sleep is separate; see `remote-mode on` and the fleet skill's references/mac-remote-access.md.
  system.activationScripts.power.text = lib.mkAfter ''
    /usr/bin/pmset -c sleep 0
  '';
}
