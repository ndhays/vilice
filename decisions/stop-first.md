# An app that cannot run twice declares `stop_first`

> Decided 2026-10-22. Spec: [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md),
> "Stop First". Amends [`quadlet-deploy.md`](quadlet-deploy.md) for one kind of app.

## What happened

The first real install of Zot, a self-hosted registry, deployed once and then could never
be redeployed. The second deploy failed its health check with `connection reset by peer`
and no log lines. Stopping Zot and deploying the same envelope worked.

Zot keeps a BoltDB cache in its storage directory, and BoltDB lets one process hold the
file. Blue/green starts the new colour beside the old one, over the same volume, so the
new Zot waited on a lock the old one held for as long as it ran. Nothing was wrong with
the image or the config; the deploy strategy assumed something about the app that was
not true.

## The decision

**An app may declare `"stop_first": true`.** The deploy stops the old colour before the
release step and the new colour, keeps its unit, and starts it again if anything after
the stop fails. The cost is a gap in service, accepted out loud.

- **A spec field, inside the digest.** How an app is replaced is part of what the deploy
  is. `rollback` and `restore` redeploy from the saved spec, so they replace the app the
  same way without being told.
- **Off unless declared.** Blue/green stays the default, because for most apps it is
  gapless and a failed deploy costs nothing.
- **The old colour stops before `release`**, not just before the new colour: the release
  container mounts the same volumes.
- **A failure restarts only what was running.** An app the operator stopped is not
  brought up by a failed deploy.
- **The field is `omitempty` in the digest**, so every spec recorded before it existed
  keeps its digest. A test pins one such digest.

## Roads not taken

- **Detect the lock and fall back.** Vilice cannot see a lock from outside the container;
  it would be guessing from a timeout, and a timeout has many causes. The app's author
  knows; they declare it.
- **A `--stop-first` flag on `deploy`.** A per-invocation choice is outside the digest, so
  a rollback would not know to repeat it — the same reason `release` is a field
  ([`declarative-deploy.md`](declarative-deploy.md)).
- **A `strategy` field** (`"blue_green"` | `"stop_first"`), as Fly.io and Docker Swarm
  name it. There are two ways, and one is the default; a boolean says that in fewer
  words. If a third way arrives, the field can become a name then.
- **Tell such apps to avoid the lock.** Some can, by configuration; many cannot, and
  Vilice runs images it did not build. The box adapts to the app, not the other way
  round.
- **Restart in place** (one colour, `systemctl restart` with a new image). It would need
  a second deploy path beside blue/green. Stop-first reuses the colours, the health
  check, the flip and the teardown, and differs only in when the old colour stops.

## What it does not fix

A gap is a gap: Caddy answers 502 from the stop until the new colour is healthy. An app
that needs no gap has to give up the lock, by its own configuration, and that is the
app's choice to make.
