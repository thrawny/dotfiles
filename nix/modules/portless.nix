{
  lib,
  pkgs,
  thrawny-pkgs,
  ...
}:
let
  adapter = pkgs.writeScriptBin "portless-tailscale" (
    builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${lib.getExe pkgs.python3}" ] (
      builtins.readFile ../../bin/portless-tailscale
    )
  );
  package = thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.portless.override {
    tailscaleCommand = lib.getExe adapter;
    proxyPortCommand = "${lib.getExe adapter} proxy-port";
    extraEnvironment = {
      PORTLESS_TAILSCALE = "1";
      PORTLESS_HTTPS = "0";
      PORTLESS_SYNC_HOSTS = "0";
    };
  };
  broker = pkgs.writeScript "portless-tailscaled" (
    builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${lib.getExe pkgs.python3}" ] (
      builtins.readFile ../lib/portless-tailscaled.py
    )
  );
in
{
  environment.systemPackages = [
    package
    adapter
  ];

  # Every local UID may publish a private loopback HTTP preview. The broker
  # checks SO_PEERCRED, owns the leases, and never grants tailscale operator,
  # sudo, file-serving, Funnel, or named-Service mutation privileges.
  systemd.sockets.portless-tailscale = {
    description = "Portless private preview registration socket";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/portless-tailscale.sock";
      SocketMode = "0666";
      RemoveOnStop = true;
    };
  };
  # Daemon-launched agents have explicit PATHs, not the login-shell system PATH.
  systemd.services =
    lib.genAttrs [ "t3code" "openclaw" "hermes-agent" ] (_: {
      path = [ package ];
    })
    // {
      portless-tailscale = {
        description = "UID-owned Tailscale previews for Portless";
        requires = [ "portless-tailscale.socket" ];
        after = [
          "portless-tailscale.socket"
          "tailscaled.service"
        ];
        serviceConfig = {
          ExecStart = "${broker} --tailscale ${lib.getExe pkgs.tailscale}";
          StateDirectory = "portless";
          StateDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
          ];
          ReadWritePaths = [ "/run/lock" ];
          CapabilityBoundingSet = "";
          Restart = "on-failure";
        };
      };
    };

  system.build.portless-package = package;
}
