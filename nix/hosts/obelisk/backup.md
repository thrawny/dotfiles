# Forgejo recovery

Backup configuration lives in [backup.nix](backup.nix). The restic repository is in the R2 bucket `thrawny-backups`, under `obelisk/forgejo`.

## Credentials

Obelisk uses root-owned files with mode `0600` in `/etc/backup`, which has mode `0700`:

- `r2.env`: bucket-scoped S3 credentials.
- `restic-password`: encryption password, also saved in 1Password.
- `repository`: full restic repository URL.

The workstation copy of the R2 credentials is at `~/.config/backup/thrawny-backups-r2.env`. Keep these credentials and the repository URL in 1Password too. R2 credentials can be replaced; the restic password cannot be recovered from R2.

## Restore

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
