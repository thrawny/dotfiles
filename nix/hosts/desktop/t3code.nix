{
  config,
  lib,
  pkgs,
  thrawny-pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
  home = config.users.users.${username}.home;
  package = thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.t3code-nightly;
  # Match the M1's local and Tailscale HTTPS ports.
  port = 4773;
  httpsPort = 8445;
  tailscale = lib.getExe config.services.tailscale.package;
in
{
  home-manager.users.${username}.home.packages = [ package ];

  # A system unit running as the primary user starts at boot without requiring
  # a graphical login and uses the user's repositories and provider credentials.
  systemd.services.t3code = {
    description = "T3 Code workstation server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      HOME = home;
      PATH = lib.mkForce (
        lib.concatStringsSep ":" [
          "/etc/profiles/per-user/${username}/bin"
          "${home}/.nix-profile/bin"
          "${home}/.local/bin"
          "${home}/dotfiles/bin"
          "/run/current-system/sw/bin"
        ]
      );
      T3CODE_HOME = "${home}/.t3";
      T3CODE_TELEMETRY_ENABLED = "false";
    };
    serviceConfig = {
      User = username;
      WorkingDirectory = home;
      ExecStart = lib.escapeShellArgs [
        (lib.getExe package)
        "serve"
        "--base-dir"
        "${home}/.t3"
        "--host"
        "127.0.0.1"
        "--port"
        (toString port)
        home
      ];
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 90;
      UMask = "0077";
    };
  };

  systemd.services.t3code-tailscale-serve = {
    description = "Tailscale HTTPS access to workstation T3 Code";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "tailscaled.service"
      "t3code.service"
    ];
    after = [
      "tailscaled.service"
      "t3code.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tailscale} serve --bg --yes --https=${toString httpsPort} http://127.0.0.1:${toString port}";
      ExecStop = "${tailscale} serve --https=${toString httpsPort} off";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = 90;
      UMask = "0077";
    };
  };
}
