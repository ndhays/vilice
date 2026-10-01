# Backup engine — restic, generic over volumes

How Steward backs up app data (and its own record), and why it's shaped this way.
Settles the **Backup engine** thread in `decisions/open/vilice-open-questions.md`.

## restic (vs Kopia / Borg)

restic, because it's the most Steward-shaped option:

- **Single static Go binary, no deps** — the same shape as Steward itself; one more file
  `prepare` installs and `doctor` checks, nothing to run resident.
- **Client-side encryption, operator-held key** — the repo is encrypted *before* it
  leaves the box, so the destination only ever sees ciphertext. The backup can live on
  hostile infra (any S3, a rented box) and stay sovereign — Agora's "make capture
  expensive," literally.
- **Destination-agnostic** — local, SFTP, S3-compatible (so self-hosted MinIO/garage),
  rclone backends. Never locked to one vendor.
- **Mature, BSD-2, trusted crypto.** Borrow the deep.

Kopia (also Go, also client-encrypted) is the closest alternative and a fine fallback;
restic wins on maturity and simplicity. Borg is good but Python and needs Borg installed
on the remote — less aligned.

## Generic over volumes, not database-aware

Steward backs up an app's **declared volumes** (a named volume via its podman mountpoint,
a bind mount via its host path) plus the **digest-tagged spec**, so a snapshot is
self-contained: the data, and how to redeploy. Restore = restic-restore + redeploy the
pinned image.

It does **not** learn what Postgres or SQLite is. Baking `pg_dump`/`sqlite .backup`
drivers into the privileged CLI would grow the ceiling (invariant 3) with per-engine
knowledge and credentials. Instead an app that needs a consistent dump declares a
**backup hook** — a command run *inside its container* before the snapshot
(`pg_dump -Fc -f /data/dump.pgc`) that writes into a declared volume. The app owns its
own consistency; Steward stays database-agnostic. (Folds part of the "hooks" question in
`open/deploy-config-model.md`.) **SQLite is the first proof** — it's just a file in the
volume, and Steward Console-on-box dogfoods it; Postgres rides the hook.

## Secrets are never in a backup

App secrets live host-side in the podman secret store and are **re-suppliable** via the
deploy envelope. So backups capture image + config + data, never secret *values*; restore
redeploys and the operator re-provides secrets. A backup repo never holds plaintext
secrets — and `backup --machine` explicitly **excludes `/var/lib/steward/secrets/`** (never
back the restic password into the repo it unlocks).

## The restic password lives with the steward user

The repo URL (not secret) is in `/var/lib/steward/backup.json`; the **password** is in
`/var/lib/steward/secrets/restic` (`0700` dir, `0600` file), passed via
`RESTIC_PASSWORD_FILE` — never argv. It's there, not `/etc` or `/root`, because everything
but `prepare`/`harden` runs as the **steward** user, so the spot must be steward-readable.
Encrypted-at-rest custody (age / `pass` / `systemd-creds`) is a later god-key-custody
upgrade that wraps the whole `secrets/` dir; minimal plaintext-file custody is enough now.

## Off-host shipping rides along — but only the snapshot half

`backup --machine` snapshots Steward's own record dir off-box, which is the coarse 80% of
"off-host shipping": the record, off the box, at snapshot cadence.

What it is **not** is *streaming* (zero-loss-window). That stays a separate, open item —
and the earlier "SQLite + Litestream for the record" sketch is **reconsidered here**: the
record is **append-only**, so it doesn't need Litestream (whose value is replicating a
*mutable* DB), and moving it to SQLite would cost the `chattr +a` immutability and the
zero-dep binary. So:

- **The record stays JSONL** on the box (immutable, zero-dep, simple).
- If/when off-box *streaming* + queryable reads are wanted, **ship the append-only log and
  project it into SQLite off-box** — the box stays simple, Steward Console's read side gets SQL
  (the CQRS "consume the shipped dump" model).
- **Litestream is reserved for app SQLite databases** (mutable, genuinely want continuous
  replication), complementing restic's snapshots — not for the record.
