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
