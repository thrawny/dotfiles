{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.tailscaleServe;
in
{
  options.services.tailscaleServe = {
    enable = lib.mkEnableOption "declarative Tailscale Serve service advertisements";

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              serviceName = lib.mkOption {
                type = lib.types.str;
                default = "svc:${name}";
                description = "Tailscale Service name to advertise.";
              };

              target = lib.mkOption {
                type = lib.types.str;
                description = "Local target passed to tailscale serve.";
              };

              httpsPort = lib.mkOption {
                type = lib.types.port;
                default = 443;
                description = "HTTPS port exposed by the Tailscale Service.";
              };

              wants = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Additional units wanted before advertising this service.";
              };

              after = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Additional units ordered before advertising this service.";
              };
            };
          }
        )
      );
      default = { };
      description = "Tailscale Services to advertise from this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (
      name: service:
      lib.nameValuePair "tailscale-serve-${name}" {
        description = "Advertise Tailscale Service ${service.serviceName}";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ]
        ++ service.wants;
        after = [
          "tailscaled.service"
          "network-online.target"
        ]
        ++ service.after;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe pkgs.tailscale} serve --service=${lib.escapeShellArg service.serviceName} --yes --https=${toString service.httpsPort} ${lib.escapeShellArg service.target}";
          ExecStop = "${lib.getExe pkgs.tailscale} serve clear ${lib.escapeShellArg service.serviceName}";
          Restart = "on-failure";
          RestartSec = 10;
        };
      }
    ) cfg.services;
  };
}
