{
  config,
  lib,
  pkgs,
  ...
}:
let
  # TODO: replace with your actual tailnet domain
  forgejoDomain = "${config.networking.hostName}.TAILNET_NAME.ts.net";
  forgejoPort = 3000;
in
{
  services.forgejo = {
    enable = true;
    lfs.enable = true;
    database.type = "postgres";
    settings = {
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejoPort;
      };
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;
      "ssh".DISABLE_SSH = true;
    };
  };

  services.postgresql.enable = true;

  systemd.services.tailscale-serve-forgejo = {
    description = "Configure Tailscale Serve for Forgejo";
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled.service" ];
    after = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
      "forgejo.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe pkgs.tailscale} serve --bg --https 443 http://127.0.0.1:${toString forgejoPort}";
      ExecStop = "${lib.getExe pkgs.tailscale} serve off";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
