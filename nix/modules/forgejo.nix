{
  config,
  ...
}:
let
  forgejoDomain = "forgejo.${config.dotfiles.tailnetDomain}";
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

  services.tailscaleServe.services.forgejo = {
    target = "http://127.0.0.1:${toString forgejoPort}";
    wants = [ "forgejo.service" ];
    after = [ "forgejo.service" ];
  };
}
