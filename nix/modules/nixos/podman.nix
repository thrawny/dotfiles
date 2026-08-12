{
  config,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
in
{
  environment.systemPackages = [ pkgs.podman-compose ];

  security.unprivilegedUsernsClone = true;

  users = {
    groups.docker = { };
    users.${username}.autoSubUidGidRange = true;
  };

  virtualisation = {
    containers.enable = true;
    docker.enable = false;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
