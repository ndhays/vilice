# Backup engine — restic, generic over volumes

> Settles the backup-engine thread in
> [`open/vilice-open-questions.md`](open/vilice-open-questions.md).

## restic

- **One static Go binary, no deps** — one more file `prepare` installs and `doctor`
  checks; nothing resident.
- **Client-side encryption, operator-held key** — the repo is encrypted before it leaves
  the box, so it can live on infrastructure you do not trust.
- **Destination-agnostic** — local, SFTP, S3-compatible, rclone backends.
- **Mature, BSD-2.**

Kopia (Go, client-encrypted) is the closest alternative and a fine fallback; restic wins
on maturity. Borg is Python and needs Borg on the remote.

## Generic over volumes, not database-aware

Vilice backs up an app's **declared volumes** plus the **digest-tagged spec**, so a
snapshot holds the data and how to redeploy. Restore is restic-restore plus a redeploy of
the pinned image.

It does not learn what Postgres or SQLite is. Dump drivers in the privileged CLI would
grow the ceiling (invariant 3) with per-engine knowledge and credentials. An app that
needs a consistent dump declares a **backup hook** — a command run inside its container
before the snapshot, writing into a declared volume.

## Secrets are never in a backup

App secrets live in the Podman secret store and are re-supplied through the deploy
envelope. Backups capture image, config and data, never secret values. `backup --machine`
excludes `/var/lib/vilice/secrets/`, so the restic password is never backed into the repo
it unlocks.

## The restic password lives with the `_vilice` user

The repo URL is in `/var/lib/vilice/backup.json`; the password is in
`/var/lib/vilice/secrets/restic` (`0700` dir, `0600` file), passed by
`RESTIC_PASSWORD_FILE`, never argv. It is there, not `/etc` or `/root`, because everything
but the root commands runs as `_vilice`. Encrypted custody (age / `pass` /
`systemd-creds`) is a later upgrade for the whole `secrets/` dir.

## Off-host shipping: the snapshot half only

`backup --machine` snapshots the record dir off-box at snapshot cadence. It is not
streaming.

**Road not taken: SQLite + Litestream for the record.** The record is append-only, so it
does not need Litestream, and SQLite would cost the `chattr +a` immutability and the
zero-dep binary. The record stays JSONL. If streaming and SQL reads are wanted, ship the
log and project it into SQLite off-box. Litestream is for app SQLite databases.
