{
  config,
  lib,
  pkgs,
  ...
}:
let
  forgejo = config.services.forgejo;
  staging = "/var/lib/forgejo-backup";
  marker = "/run/restic-backups-forgejo/restart-forgejo";
  t3Staging = "/var/lib/t3code-backup";
in
{
  systemd.tmpfiles.rules = [ "d /etc/backup 0700 root root -" ];

  services.restic.backups.forgejo = {
    environmentFile = "/etc/backup/r2.env";
    passwordFile = "/etc/backup/restic-password";
    repositoryFile = "/etc/backup/repository";
    initialize = true;
    paths = [ staging ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
    pruneOpts = [
      "--path ${staging}"
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
    checkOpts = [ "--read-data-subset=10%" ];

    backupPrepareCommand = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      umask 077
      # Mark before stopping so ExecStopPost can recover even after interruption.
      ${pkgs.systemd}/bin/systemctl is-active --quiet forgejo.service
      touch ${marker}
      ${pkgs.systemd}/bin/systemctl stop forgejo.service
      rm -rf ${staging}
      mkdir -p ${staging}/forgejo
      ${pkgs.rsync}/bin/rsync -a --exclude=/log/ --exclude=/dump/ \
        ${lib.escapeShellArg forgejo.stateDir}/ ${staging}/forgejo/
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dump --format=custom \
        ${lib.escapeShellArg forgejo.database.name} > ${staging}/forgejo.pgdump
      ${pkgs.systemd}/bin/systemctl start forgejo.service
      rm -f ${marker}
    '';
    backupCleanupCommand = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      if test -e ${marker}; then
        ${pkgs.systemd}/bin/systemctl start forgejo.service
        rm -f ${marker}
      fi
      rm -rf ${staging}
    '';
  };

  services.restic.backups.t3code = {
    environmentFile = "/etc/backup/r2.env";
    passwordFile = "/etc/backup/restic-password";
    repositoryFile = "/etc/backup/repository";
    initialize = true;
    paths = [ t3Staging ];
    extraBackupArgs = [ "--tag t3code" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/6:15:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
    pruneOpts = [
      "--path ${t3Staging}"
      "--keep-hourly 24"
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
    backupPrepareCommand = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      umask 077
      home=/srv/t3code
      userdata="$home/.t3code/userdata"
      test -s "$userdata/statev2.sqlite"
      rm -rf ${t3Staging}
      mkdir -p ${t3Staging}/.t3code/userdata ${t3Staging}/.codex
      # SQLite's online backup includes committed WAL data without stopping T3.
      for source in "$userdata"/state*.sqlite "$home/.codex"/state_*.sqlite; do
        test -s "$source" || continue
        relative="''${source#"$home/"}"
        destination="${t3Staging}/$relative"
        ${pkgs.sqlite}/bin/sqlite3 -readonly "$source" ".timeout 30000" ".backup '$destination'"
        test "$(${pkgs.sqlite}/bin/sqlite3 -readonly "$destination" 'PRAGMA quick_check;')" = ok
      done
      for relative in .t3code/userdata/attachments .codex/sessions .codex/archived_sessions .claude/projects; do
        if test -d "$home/$relative"; then
          mkdir -p "${t3Staging}/$relative"
          ${pkgs.rsync}/bin/rsync -a "$home/$relative/" "${t3Staging}/$relative/"
        fi
      done
      for name in settings.json keybindings.json environment-id; do
        if test -f "$userdata/$name"; then
          cp "$userdata/$name" "${t3Staging}/.t3code/userdata/$name"
        fi
      done
    '';
    backupCleanupCommand = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      rm -rf ${t3Staging}
    '';
  };

  systemd.services.restic-backups-t3code = {
    unitConfig.ConditionPathExists = [
      "/etc/backup/r2.env"
      "/etc/backup/restic-password"
      "/etc/backup/repository"
      "/srv/t3code/.t3code/userdata/statev2.sqlite"
    ];
    serviceConfig = {
      UMask = "0077";
      TimeoutStartSec = "2h";
      TimeoutStopSec = "5min";
    };
  };

  systemd.services.restic-backups-forgejo = {
    # Do not stop Forgejo until manual credential provisioning is complete.
    unitConfig.ConditionPathExists = [
      "/etc/backup/r2.env"
      "/etc/backup/restic-password"
      "/etc/backup/repository"
    ];
    serviceConfig = {
      UMask = "0077";
      TimeoutStartSec = "2h";
      TimeoutStopSec = "5min";
    };
  };
}
