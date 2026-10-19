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
  activationPidFile = "${state}/userdata/activation.pid";
  agentName = "org.nix-community.home.t3code";
  agentFile = "${home}/Library/LaunchAgents/${agentName}.plist";
  recovery = pkgs.writeShellScript "t3code-recovery" ''
    set -eu
    # An activation may deliberately unload T3 while installing its replacement.
    if [[ -r ${lib.escapeShellArg activationPidFile} ]]; then
      activationPid=""
      IFS= read -r activationPid < ${lib.escapeShellArg activationPidFile} || true
      if [[ "$activationPid" =~ ^[0-9]+$ ]] && kill -0 "$activationPid" 2>/dev/null; then
        exit 0
      fi
    fi
    if ! /bin/launchctl print "gui/$UID/${agentName}" >/dev/null 2>&1; then
      echo "Recovering unloaded T3 Code launch agent."
      /bin/launchctl bootstrap "gui/$UID" ${lib.escapeShellArg agentFile}
    fi
  '';
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

    # Home Manager can exit after unloading an agent but before reinstalling it.
    home.activation.t3codeRecovery =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "t3codeDirectories" ]
        ''
          if [[ -z "''${DRY_RUN_CMD:-}" ]]; then
            printf '%s\n' "$$" > ${lib.escapeShellArg activationPidFile}
            t3codePreviousExitTrap=$(trap -p EXIT)
            t3codeActivationFinished() {
              local activationExit=$?
              trap - EXIT
              local agentDomain="gui/$UID"
              local agentName=${lib.escapeShellArg agentName}
              local agentFile=${lib.escapeShellArg agentFile}
              if ! /bin/launchctl print "$agentDomain/$agentName" >/dev/null 2>&1; then
                echo "T3 Code was left unloaded; recovering its installed launch agent." >&2
                if ! /bin/launchctl bootstrap "$agentDomain" "$agentFile"; then
                  echo "T3 Code recovery failed. Inspect ${logs}/launchd.log." >&2
                  activationExit=1
                fi
              fi
              if ! ${lib.getExe pkgs.curl} --fail --silent --show-error --output /dev/null \
                --noproxy '*' --connect-timeout 1 --max-time 2 \
                --retry 15 --retry-delay 1 --retry-connrefused --retry-max-time 30 \
                http://127.0.0.1:${toString cfg.port}/; then
                echo "T3 Code did not become healthy. Inspect ${logs}/launchd.log." >&2
                activationExit=1
              fi
              rm -f ${lib.escapeShellArg activationPidFile}
              # Run Home Manager's original cleanup with the final exit status.
              (
                eval "$t3codePreviousExitTrap"
                exit "$activationExit"
              ) || true
              exit "$activationExit"
            }
            trap t3codeActivationFinished EXIT
          fi
        '';

    launchd.agents = {
      t3code-recovery = {
        enable = true;
        config = {
          ProgramArguments = [ (toString recovery) ];
          RunAtLoad = true;
          StartInterval = 30;
          StandardOutPath = "${logs}/recovery.log";
          StandardErrorPath = "${logs}/recovery.log";
        };
      };

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
