{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.tailscaleServe;
  # Serve config and AdvertiseServices are shared daemon state. Keep the same
  # lock for every start/stop, including during concurrent NixOS activation.
  # Do not use per-unit RuntimeDirectory cleanup: it could unlink a held lock.
  lockFile = "/run/lock/dotfiles-tailscale-serve.lock";
  flock = lib.getExe' pkgs.util-linux "flock";
  tailscale = lib.getExe pkgs.tailscale;
  lockedTailscale = "${flock} --exclusive --wait 60 ${lockFile} ${tailscale}";
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
          ExecStart = "${lockedTailscale} serve --service=${lib.escapeShellArg service.serviceName} --yes --https=${toString service.httpsPort} ${lib.escapeShellArg service.target}";
          ExecStop = "${lockedTailscale} serve clear ${lib.escapeShellArg service.serviceName}";
          UMask = "0077";
          TimeoutStartSec = 90;
          TimeoutStopSec = 90;
          Restart = "on-failure";
          RestartSec = 10;
        };
      }
    ) cfg.services;

    system.build.tailscale-serve-check =
      let
        spec = pkgs.writeText "tailscale-serve-units.json" (
          builtins.toJSON {
            inherit lockFile flock tailscale;
            services = lib.mapAttrs (name: service: {
              inherit (service) serviceName target httpsPort;
              inherit (config.systemd.services."tailscale-serve-${name}".serviceConfig) ExecStart ExecStop;
            }) cfg.services;
          }
        );
      in
      pkgs.runCommand "tailscale-serve-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../../bin/check-tailscale-serve} ${spec}
        touch "$out"
      '';
  };
}
