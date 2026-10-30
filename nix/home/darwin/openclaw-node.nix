{
  config,
  lib,
  pkgs,
  nix-openclaw,
  ...
}:
let
  cfg = config.dotfiles.openclawNode;
  package = nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
  logs = "${config.home.homeDirectory}/Library/Logs/openclaw-node";
in
{
  options.dotfiles.openclawNode = {
    enable = lib.mkEnableOption "headless OpenClaw companion node";
    host = lib.mkOption {
      type = lib.types.str;
      description = "Existing gateway TLS hostname.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ package ];
    home.activation.openclawNodeLogs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg logs}
    '';
    launchd.agents.openclaw-node = {
      enable = true;
      config = {
        ProgramArguments = [
          "${package}/bin/openclaw"
          "node"
          "run"
          "--host"
          cfg.host
          "--port"
          "443"
          "--tls"
          "--display-name"
          "M1"
          "--commands"
          "system.run.prepare,system.run,system.which,system.execApprovals.get"
        ];
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          PATH = lib.concatStringsSep ":" (
            [ "${config.home.profileDirectory}/bin" ]
            ++ map (lib.replaceStrings
              [ "$HOME" "\${HOME}" ]
              [ config.home.homeDirectory config.home.homeDirectory ]
            ) config.home.sessionPath
            ++ [
              "/nix/var/nix/profiles/default/bin"
              "/opt/homebrew/bin"
              "/usr/local/bin"
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ]
          );
        };
        WorkingDirectory = config.home.homeDirectory;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 15;
        StandardOutPath = "${logs}/node.log";
        StandardErrorPath = "${logs}/node.log";
      };
    };
  };
}
