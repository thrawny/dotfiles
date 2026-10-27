# Obelisk backups and recovery

Backup configuration lives in [backup.nix](backup.nix). The restic repository is in the R2 bucket `thrawny-backups`, under `obelisk/forgejo`.

Forgejo and T3 share this encrypted repository. Each job limits retention to its
own staging path so Forgejo's daily policy cannot remove T3's frequent snapshots.

## T3 transcripts

T3 backs up every six hours, with up to 15 minutes of jitter. Retention keeps
24 hourly buckets (at this schedule, approximately six days), seven daily,
four weekly and three monthly snapshots. Snapshots have the `t3code` tag.

The backup includes T3's current and legacy conversation databases, attachments,
settings, keybindings and environment identity, plus Codex session transcripts
and state indexes and Claude project transcripts. SQLite databases use online
snapshots and pass `quick_check`; T3 keeps running. Each database is individually
consistent, but files and databases are not one atomic cross-application snapshot;
an active transcript can end mid-turn. Worktrees, dependencies, caches, browser
profiles and provider login credentials are not included. This protects history,
not uncommitted source code or a complete signed-in T3 installation.

Run a backup and inspect snapshots as root:

```sh
systemctl start restic-backups-t3code.service
restic-t3code snapshots --tag t3code
restic-t3code restore latest --tag t3code --target /var/tmp/t3code-restore --verify
```

Recovered files are under `/var/tmp/t3code-restore/var/lib/t3code-backup/`, with
paths relative to `/srv/t3code`. Restore into a separate directory first and
verify the databases with `sqlite3 DATABASE 'PRAGMA quick_check;'`. For live
recovery, stop T3 and its agent sessions, preserve the existing data, then restore
the selected files with ownership `t3code:t3code`. Move aside the matching old
SQLite `-wal` and `-shm` files before replacing a database. Start T3 and verify
thread history and attachments before deleting the recovery files. Provider
authentication must be provisioned separately on a replacement machine.

The staging copy is deleted after each run, including failures. Check
`journalctl -u restic-backups-t3code` for failures; there are no external alerts.

## Credentials

Obelisk uses root-owned files with mode `0600` in `/etc/backup`, which has mode `0700`:

- `r2.env`: bucket-scoped S3 credentials.
- `restic-password`: encryption password, also saved in 1Password.
- `repository`: full restic repository URL.

The workstation copy of the R2 credentials is at `~/.config/backup/thrawny-backups-r2.env`. Keep these credentials and the repository URL in 1Password too. R2 credentials can be replaced; the restic password cannot be recovered from R2.

## Forgejo restore

On a replacement host, deploy the matching NixOS configuration and provision the credential files first. This recreates the Forgejo PostgreSQL role and database. Run the following as root on the recovery host:

```sh
systemctl stop restic-backups-forgejo.timer
# Wait for any running backup to finish before proceeding.
systemctl is-active restic-backups-forgejo.service
restic-forgejo snapshots
install -d -m 0700 /var/tmp/forgejo-restore
restic-forgejo restore latest --target /var/tmp/forgejo-restore --verify
```

Recovered data is under `/var/tmp/forgejo-restore/var/lib/forgejo-backup/`:

- `forgejo/`: repositories, attachments, application secrets and other Forgejo state.
- `forgejo.pgdump`: PostgreSQL dump. Inspect its table of contents with `pg_restore --list`.

For full recovery:

1. Stop `forgejo.service` and preserve any existing files and database before replacing them.
2. Restore `forgejo/` into `/var/lib/forgejo`, preserving ownership and permissions.
3. Restore the dump into an empty Forgejo database as the PostgreSQL administrator using `pg_restore --exit-on-error --dbname=forgejo`. Preserve the role ownership recorded in the dump.
4. Rebuild NixOS-managed symlinks with the matching configuration before starting Forgejo.
5. Verify login, repositories, issues and attachments. Restart the backup timer and delete the plaintext recovery files when finished.

## Gotchas

- Do not configure R2 object expiry for this repository. Restic manages retention.
- External failure alerts are not configured. Check `journalctl -u restic-backups-forgejo` and the latest snapshot time.
- Missing credential files cause scheduled runs to skip.
- Bucket-scoped credentials can delete every repository in `thrawny-backups`. Separate prefixes do not isolate access.
