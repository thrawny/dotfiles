{
  config,
  lib,
  pkgs,
  thrawny-pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  home = config.home.homeDirectory;
  state = "${home}/.t3";
  logs = "${state}/userdata/logs";
in
{
  options.dotfiles.t3code = {
    enable = lib.mkEnableOption "the T3 Code server on macOS";
    package = lib.mkOption {
      type = lib.types.package;
      default = thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.t3code-nightly;
      description = "T3 Code server package.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback port for the T3 Code server.";
    };
    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Tailscale Serve HTTPS port for the T3 Code server.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.activation.t3codeDirectories =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
        ''
          run mkdir -p ${lib.escapeShellArg logs}
        '';

    launchd.agents = {
      t3code = {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe cfg.package)
            "serve"
            "--base-dir"
            state
            "--host"
            "127.0.0.1"
            "--port"
            (toString cfg.port)
            home
          ];
          EnvironmentVariables = {
            HOME = home;
            PATH = lib.concatStringsSep ":" [
              "${config.home.profileDirectory}/bin"
              "${home}/.local/bin"
              "${home}/dotfiles/bin"
              "/nix/var/nix/profiles/default/bin"
              "/opt/homebrew/bin"
              "/run/current-system/sw/bin"
              "/usr/local/bin"
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ];
            T3CODE_HOME = state;
            T3CODE_TELEMETRY_ENABLED = "false";
          };
          WorkingDirectory = home;
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 10;
          ExitTimeOut = 90;
          StandardOutPath = "${logs}/launchd.log";
          StandardErrorPath = "${logs}/launchd.log";
        };
      };

      t3code-tailscale-serve = {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe pkgs.tailscale)
            "serve"
            "--bg"
            "--https=${toString cfg.httpsPort}"
            "http://127.0.0.1:${toString cfg.port}"
          ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          StandardOutPath = "${logs}/tailscale-serve.log";
          StandardErrorPath = "${logs}/tailscale-serve.log";
        };
      };
    };
  };
}
