{
  config,
  lib,
  llm-agents,
  pkgs,
  thrawny-pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  home = config.home.homeDirectory;
  state = "${home}/.t3";
  llmPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  providerWithDirenv =
    name: package:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.direnv ];
      text = ''
        export DIRENV_LOG_FORMAT=
        exec direnv exec "$PWD" ${lib.getExe package} "$@"
      '';
    };
  codexWithDirenv = providerWithDirenv "t3code-codex" llmPkgs.codex;
  claudeWithDirenv = providerWithDirenv "t3code-claude" llmPkgs.claude-code;
  launcher = pkgs.writeShellScript "t3code-launch" ''
    set -e
    if [[ -z "''${SANDBOX:-}" && -r "$HOME/.secrets" ]]; then
      set -a
      . "$HOME/.secrets"
      set +a
    fi
    exec ${lib.getExe cfg.package} serve \
      --base-dir ${lib.escapeShellArg state} \
      --host 127.0.0.1 --port ${toString cfg.port} ${lib.escapeShellArg home}
  '';
in
{
  options.dotfiles.t3code = {
    enable = lib.mkEnableOption "the T3 Code user server on Linux";
    package = lib.mkOption {
      type = lib.types.package;
      default = thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.t3code-nightly;
      description = "T3 Code server package.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 4773;
      description = "Loopback port for the T3 Code server.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    programs.direnv.config.whitelist.prefix = [ "${state}/worktrees" ];
    # T3 command shells do not read the interactive .zshrc hook.
    programs.zsh.envExtra = ''
      if [[ -n "''${T3CODE_HOME:-}" && -z "''${T3CODE_DIRENV_ZSHENV:-}" ]]; then
        export T3CODE_DIRENV_ZSHENV=1
        export DIRENV_LOG_FORMAT="''${DIRENV_LOG_FORMAT-}"
        eval "$(${lib.getExe pkgs.direnv} export zsh 2>/dev/null || true)"
        unset T3CODE_DIRENV_ZSHENV
      fi
    '';

    home.activation.t3codeProviders = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
      if [[ -z "''${DRY_RUN_CMD:-}" ]]; then
        run mkdir -p ${lib.escapeShellArg "${state}/userdata"}
        settings=${lib.escapeShellArg "${state}/userdata/settings.json"}
        settingsInput="$settings"
        if [[ ! -f "$settingsInput" ]]; then
          settingsInput=${pkgs.writeText "t3code-empty-settings.json" "{}"}
        fi
        settingsTmp=$(mktemp "$settings.XXXXXX")
        ${lib.getExe pkgs.jq} \
          --arg codex ${lib.escapeShellArg (lib.getExe codexWithDirenv)} \
          --arg claude ${lib.escapeShellArg (lib.getExe claudeWithDirenv)} '
            .providers.codex.binaryPath = $codex
            | .providers.claudeAgent.binaryPath = $claude
            | .providerInstances.codex //= {driver: "codex", enabled: true, config: {}}
            | .providerInstances.claudeAgent //= {driver: "claudeAgent", enabled: true, config: {}}
            | .providerInstances.codex.config.binaryPath = $codex
            | .providerInstances.claudeAgent.config.binaryPath = $claude
          ' "$settingsInput" > "$settingsTmp"
        chmod 600 "$settingsTmp"
        mv "$settingsTmp" "$settings"
      fi
    '';

    systemd.user.services.t3code = {
      Unit.Description = "T3 Code headless server";
      Service = {
        ExecStart = toString launcher;
        WorkingDirectory = home;
        Environment = [
          "HOME=${home}"
          "PATH=${config.home.profileDirectory}/bin:${home}/.local/bin:${home}/dotfiles/bin:/run/current-system/sw/bin"
          "T3CODE_HOME=${state}"
          "T3CODE_TELEMETRY_ENABLED=false"
        ];
        Restart = "always";
        RestartSec = 10;
        TimeoutStopSec = 90;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
