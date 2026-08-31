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
  environment.systemPackages = [
    pkgs.docker-client
    pkgs.podman-compose
  ];

  users.users.${username}.autoSubUidGidRange = true;

  virtualisation = {
    containers.enable = true;
    docker.enable = false;
    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Local containers use rootless Podman. Keep the system-wide rootful API
  # socket disabled; the per-user Podman socket remains available.
  systemd.sockets.podman.wantedBy = lib.mkForce [ ];
}
