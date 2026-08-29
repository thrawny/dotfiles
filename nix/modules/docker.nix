{
  config,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
in
{
  environment.systemPackages = [ pkgs.docker-compose ];

  virtualisation = {
    containers.enable = true;
    docker.enable = true;
    podman.enable = false;
  };

  users.users.${username}.autoSubUidGidRange = true;
}
