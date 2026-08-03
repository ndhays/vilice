# steward

The program on every machine — the one door to the box's power. **Just a CLI — no
daemon.** `sshd` invokes it for privileged actions (over a scoped key pinned to a
forced command); `systemd` invokes `steward snapshot` on a timer to keep the record.
It borrows its residency from the system rather than supervising itself.

The command surface and the auth model (scoped SSH, the legible ceiling) are
specified in [`site/content/index.md`](../site/content/index.md) and, in depth, in
[`blueprint/steward/`](../blueprint/steward/). Code is a projection of those.

## Layout

```
cmd/steward/        the wiring: register the packs, hand argv to the core
internal/core/      the trust layer — dispatch, gate, record, ceiling, auth
internal/pack/app/  steward-app: deploy, lifecycle, backup, observe
```

The core never learns what a verb does; a pack never gets a way in that skips the
gate. See [`blueprint/steward/packs.md`](../blueprint/steward/packs.md).

## Build

```bash
make build        # → bin/steward   (Go 1.22+)
make test
steward help
```

## Status

The core is implemented and box-verified: provision (`prepare`/`harden`), auth
(`authorize`/`revoke` + the `_exec` gate), deploy + lifecycle, observe
(`status`/`logs`/`doctor`), the append-only record, and `snapshot`. The core/pack
line is drawn: one binary, internally layered, with `steward-app` as the only pack.
