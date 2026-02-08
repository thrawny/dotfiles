{
  lib,
  pkgs,
  config,
  ...
}:
let
  openclawPath = lib.concatStringsSep ":" (
    map toString (
      config.home.sessionPath
      ++ [
        "${config.home.profileDirectory}/bin"
        "/run/current-system/sw/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ]
    )
  );
  openclawInstallIfMissing = pkgs.writeShellScript "openclaw-install-if-missing" ''
    set -euo pipefail

    if ! command -v openclaw >/dev/null 2>&1; then
      # Official installer from docs: https://docs.openclaw.ai/install
      ${pkgs.curl}/bin/curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh \
        | ${pkgs.bash}/bin/bash -s -- --no-onboard --no-prompt </dev/null
    fi
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  # OpenClaw update runbook:
  # - Updates are daily via `openclaw-update.timer`.
  # - No version pinning; OpenClaw remains npm/official-installer managed.
  # - If OpenClaw is missing, install via the official installer script first.
  # - If update fails: `journalctl --user -u openclaw-update.service` then
  #   run `openclaw update --yes` manually.
  systemd.user.services.openclaw-update = {
    Unit.Description = "Update OpenClaw CLI (official installer-managed gateway)";
    Service = {
      Type = "oneshot";
      Environment = "PATH=${openclawPath}";
      ExecStartPre = "${openclawInstallIfMissing}";
      ExecStart = ''${pkgs.bash}/bin/bash -lc "openclaw update --yes --timeout 1800"'';
      ExecStartPost = ''${pkgs.bash}/bin/bash -lc "openclaw gateway status --json"'';
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.user.timers.openclaw-update = {
    Unit.Description = "Run OpenClaw update daily";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
      Unit = "openclaw-update.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Keep official installer-managed gateway service and only manage PATH override.
  home.file.".config/systemd/user/openclaw-gateway.service.d/10-path-override.conf".text = ''
    [Service]
    Environment=PATH=${openclawPath}
  '';
}
