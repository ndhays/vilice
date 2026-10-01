# vilice

The program on every machine — the one door to the box's power. **Just a CLI — no
daemon.** `sshd` invokes it for privileged actions (over a scoped key pinned to a
forced command); `systemd` invokes `vilice snapshot` on a timer to keep the record.
It borrows its residency from the system rather than supervising itself.

The command surface and the auth model (scoped SSH, the legible ceiling) are
specified in [`site/content/index.md`](../site/content/index.md) and, in depth, in
[`blueprint/vilice/`](../blueprint/vilice/). Code is a projection of those.

## Layout

```
cmd/vilice/        the wiring: register the app layer, hand argv to the core
internal/core/      the trust layer — dispatch, gate, record, ceiling, auth
internal/app/       the app layer: deploy, lifecycle, backup, observe
```

The core never learns what a verb does; the app layer never gets a way in that skips
the gate. See [`blueprint/vilice/overview.md`](../blueprint/vilice/overview.md).

## Build

```bash
make build        # → bin/vilice   (Go 1.22+)
make test
vilice help
```

## Status

The core is implemented and box-verified: provision (`prepare`/`harden`), auth
(`authorize`/`revoke` + the `_exec` gate), deploy + lifecycle, observe
(`status`/`logs`/`doctor`), the append-only record, and `snapshot`. One binary,
internally layered: a trust core and the app layer it dispatches to.
