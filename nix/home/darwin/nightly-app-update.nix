{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  cfg = config.dotfiles.nightlyAppUpdate;
  state = "${config.home.homeDirectory}/.local/state/nightly-app-update";
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
      llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
    ];
    text = ''
      export PATH="/nix/var/nix/profiles/default/bin:$PATH"
      export PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo
      export GIT_TERMINAL_PROMPT=0
      export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10'
      exec python3 ${../../../scripts/nightly-app-update.py} --scheduled \
        --repo ${lib.escapeShellArg cfg.repository} \
        --task ${../../../scripts/nightly-app-update-task.md} \
        --state-dir ${lib.escapeShellArg state}
    '';
  };
  agentConfig = {
    Label = "org.nix-community.home.nightly-app-update";
    ProgramArguments = [ "${runner}/bin/nightly-app-update" ];
    # The runner gates wall time with Europe/Stockholm, independent of host TZ.
    # RunAtLoad/StartInterval also catch a missed night after login or wake.
    RunAtLoad = true;
    StartInterval = 60;
    ProcessType = "Background";
    LowPriorityIO = true;
    Nice = 10;
    EnvironmentVariables.TZ = "Europe/Stockholm";
    StandardOutPath = "${state}/scheduler.log";
    StandardErrorPath = "${state}/scheduler.log";
  };
  plist = pkgs.runCommand "nightly-app-update.plist" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 - ${pkgs.writeText "nightly-app-update.json" (builtins.toJSON agentConfig)} "$out" <<'PY'
    import json, plistlib, sys
    with open(sys.argv[1]) as source, open(sys.argv[2], "wb") as target:
        plistlib.dump(json.load(source), target)
    PY
  '';
in
{
  options.dotfiles.nightlyAppUpdate = {
    enable = lib.mkEnableOption "nightly app maintenance on M1 and Obelisk";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/factory-repos/dotfiles";
      description = "Checkout used only to discover the supported origin URL.";
    };
    plist = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = plist;
    };
  };
  config = lib.mkIf cfg.enable {
    launchd.agents.nightly-app-update = {
      enable = true;
      config = agentConfig;
    };
    home.activation.nightlyAppUpdateState =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
        ''
          run mkdir -p ${lib.escapeShellArg state}
          run chmod 0700 ${lib.escapeShellArg state}
          run ${pkgs.python3}/bin/python3 ${../../../scripts/nightly-app-update.py} \
            --initialize --state-dir ${lib.escapeShellArg state}
        '';
  };
}
