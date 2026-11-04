{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nightlyAppUpdate;
  state = "${config.home.homeDirectory}/.local/state/nightly-app-update";
  # Keep the diagnostic helper beside the runner in the immutable installation.
  source = pkgs.runCommand "nightly-app-update-source" { } ''
    mkdir -p "$out"
    cp ${../../../scripts/nightly-app-update.py} "$out/nightly-app-update.py"
    cp ${../../../scripts/openclaw-diagnostics.py} "$out/openclaw-diagnostics.py"
  '';
  runner = pkgs.writeShellApplication {
    name = "nightly-app-update";
    runtimeInputs = [
      pkgs.python3
      pkgs.git
      pkgs.openssh
      pkgs.just
      pkgs.uv
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      export PATH="/nix/var/nix/profiles/default/bin:$PATH"
      export PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo
      export GIT_TERMINAL_PROMPT=0
      export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10'
      case "''${1:-}" in
        --diagnose|--prepare|--verify) ;;
        *) echo 'Choose --diagnose, --prepare or --verify; updates belong to the T3 agent.' >&2; exit 2 ;;
      esac
      exec python3 ${source}/nightly-app-update.py "$@" \
        --repo ${lib.escapeShellArg cfg.repository} \
        --task ${../../../scripts/nightly-app-update-task.md} \
        --state-dir ${lib.escapeShellArg state}
    '';
  };

in
{
  options.dotfiles.nightlyAppUpdate = {
    enable = lib.mkEnableOption "on-demand fleet maintenance helpers (no launchd schedule)";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/factory-repos/dotfiles";
      description = "Checkout used only to discover the supported origin URL.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = runner;
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ runner ];
    # Retired: only the native T3 agent may decide to update and own its rollout.
    launchd.agents.nightly-app-update.enable = false;
  };
}
