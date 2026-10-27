{ lib, pkgs, ... }:
let
  guard = pkgs.writeShellApplication {
    name = "obelisk-storage";
    runtimeInputs = [
      pkgs.python3
      pkgs.nix
      pkgs.coreutils
      pkgs.util-linux
      pkgs.e2fsprogs
    ];
    text = ''exec python3 ${../../../bin/obelisk-storage} "$@"'';
  };
in
{
  # System builds belong on the workstation's Linux builder, never this host.
  nix.settings = {
    max-jobs = 0;
    # Nix measures space available to ordinary users, excluding the 15 GiB
    # reserve. These correspond to 20/25 GiB physically free.
    min-free = lib.mkForce (5 * 1024 * 1024 * 1024);
    max-free = lib.mkForce (10 * 1024 * 1024 * 1024);
  };

  environment.systemPackages = [ guard ];
  services.journald.settings.Journal = {
    SystemMaxUse = "256M";
    SystemKeepFree = "5G";
  };

  systemd.services.obelisk-storage = {
    description = "Collect unused Nix data before crossing Obelisk's disk floor";
    after = [ "local-fs.target" ];
    path = [ pkgs.nix ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe guard} clean";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "30min";
    };
  };
  systemd.services.obelisk-storage-reserve = {
    description = "Reserve 15 GiB of ext4 space against unprivileged writers";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe guard} reserve";
    };
  };
  systemd.timers.obelisk-storage = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "5min";
    };
  };

  # Root-run staging must leave the floor intact too. Budgets include the
  # source data plus 1 GiB for database dumps, metadata and concurrent writes.
  systemd.services.restic-backups-t3code.serviceConfig.ExecCondition =
    "${lib.getExe guard} check --copy-path /srv/t3code/.t3code/userdata --copy-path /srv/t3code/.codex/sessions --copy-path /srv/t3code/.codex/archived_sessions --copy-path /srv/t3code/.claude/projects --copy-path /srv/t3code/.codex/state_5.sqlite";
  systemd.services.restic-backups-forgejo.serviceConfig.ExecCondition =
    "${lib.getExe guard} check --copy-path /var/lib/forgejo --copy-path /var/lib/postgresql";
}
