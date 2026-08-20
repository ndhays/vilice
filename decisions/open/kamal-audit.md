# Kamal, audited against Steward

> **2026-08-19.** Kamal is the closest thing to Steward that people actually run, and the
> two have now converged enough — accessories, a release step, blue/green, auto-TLS — that
> a straight comparison is finally useful. This is a *landscape* note, not a decision:
> [`borrowed-substrate.md`](../borrowed-substrate.md) already settled that Kamal is
> **inspiration, not a dependency**, and nothing here reopens that.
>
> Grounded in Kamal's own documentation, read 2026-08-19. Where a claim rests on inference
> rather than a doc page, it says so.

---

## They are not doing the same job

**Kamal deploys your app.** Its user is the person who wrote the code, pushing it to
servers they control. Everything follows: it builds the image for you, it holds config in
your repo beside the code, and it gives you a production console because of course you want
one — it is *your* app.

**Steward is accountable for a fleet.** Its user may not have written anything, and may
have to answer afterwards for what happened on a box. Everything follows from that instead:
a hash-chained record written before the act, one door, no shell.

Most of what looks like disagreement below is these two sentences.

## Where they converged independently

Worth noting, because convergence is evidence both got something right:

| | Kamal | Steward |
|---|---|---|
| Transport | SSH, **no agent or daemon** on the box | SSH, no agent or daemon |
| Cutover | boot new container → health → proxy switches | boot new colour → health → Caddy flips |
| Edge | `kamal-proxy`, auto Let's Encrypt | Caddy, auto Let's Encrypt |
| Rollback | fast **because the old container is still local** | fast because `PrevImage` is kept local on purpose |
| Accessories | `accessories:` — image, env, volumes, files | `accessories` — image, env, volumes, secrets |
| Pruning | `retain_containers` (default 5) | `prune` keeps image + `PrevImage` |

The rollback row is the pleasing one. Kamal's rollback is a traffic switch to a container
still on the box; Steward's `prune.go` keeps the previous image local for an explicitly
stated reason — *"rollback is the emergency path — 3am, something is broken, and the last
thing it should need is a reachable registry."* Same insight, arrived at separately.

## Where they diverge, and what each buys

### The record

Kamal writes `.kamal/app-audit.log` on each server — timestamped lines naming who ran what.
`kamal audit` prints it. The documentation describes the output and says nothing about
integrity, which is itself the answer: it is a **convenience log**, not an instrument. It is
written by the tool, so anything that reaches Docker another way leaves no trace in it.

Steward's chain is hash-linked, written **before** the act, and un-bypassable because the
scoped key resolves to `_exec` and there is no second door.

*The trade:* Kamal's log tells you what Kamal did. Steward's record tells you what happened.
Steward pays for that with every restriction below.

### The shell

`kamal app exec -i 'bin/rails console'` is a first-class, documented feature, with `-i`
for interactive and `--reuse` to join the running container.

Steward refuses an empty command at **every** scope
([`no-key-gets-a-shell.md`](../no-key-gets-a-shell.md)), and offers no `exec` verb at all.

*The trade:* this is the sharpest divergence and Kamal is plainly more usable here. Steward's
position is not that consoles are bad — it is that a shell as the `steward` user could run
containers, write units and rewrite Caddy's config, and the record would show a session
opening and nothing else. One unrecorded door ends the claim, so there isn't one, and you
reach a console the way you always did: SSH as yourself.

### Image identity

Kamal tags by **git SHA** — and on a dirty tree, by `uncommitted` plus a random SHA. A tag
is a mutable pointer; two pushes can wear one name.

Steward refuses anything but `ref@sha256:…`, at the box and mirrored in the console.

*The trade:* Kamal's is friendlier and integrates with git for free. Steward's is what makes
*"which image was running"* answerable after the fact, which is the whole point of a record
that outlives the deploy.

### Accessories — the most instructive difference

Both have them; almost every property differs.

| | Kamal | Steward |
|---|---|---|
| Network | `kamal`, **shared by default** | `steward-<app>`, one per app |
| Reachable by | anything on that network | its own app, and nothing else |
| Ports | `port:` publishes host→container | none, ever — the absence *is* the isolation |
| Extra flags | `options:` passes raw Docker flags | Steward builds every flag; none pass through |
| Lifecycle | **separate** — `kamal accessory boot`, *not* updated on deploy | comes up with the app, inside the spec digest |
| Sharing | can serve several apps | belongs to exactly one |

Two honest readings of that table.

**Steward is right about the network.** A shared default means declaring that `web` needs a
database also lets every other container on the box reach it, and `options:` accepting raw
Docker flags is precisely what `FuzzAccessoryUnitShape` exists to make impossible. This is
the reasoning in
[`accessories-belong-to-one-app.md`](../accessories-belong-to-one-app.md), and seeing the
alternative shipped is a good check on it.

**Kamal may be right about the lifecycle.** *"Accessories are not updated when you deploy."*
That is a defensible call and arguably the better one for a database: you do not want
Postgres bouncing because you shipped a CSS change. Steward's accessories ride the app's
deploy, and the mitigation — an unchanged unit is left alone — narrows the blast radius
without removing it. **This is the one place the audit suggests Steward may have chosen
wrong**, and it is written up as open below.

### Secrets

Kamal keeps values in `.kamal/secrets` on the **deploying machine** (typically pulled from a
password manager), pushed to an env file on the host so they stay out of `docker inspect`.

Steward keeps them in the console, **encrypted at rest**, and resends them every deploy.

*The trade, stated plainly:* Kamal's control plane holds nothing at rest, which is a real
security advantage — there is no central store to breach. Steward chose central-encrypted to
get the self-contained deploy (no set-once ordering, no dangling secret), and accepts owning
a secret store as the cost. Both are coherent; neither is obviously better.

### Release phase

Kamal has nine lifecycle hooks and **none that runs inside the app container on the server**.
Migrations therefore go in the image entrypoint (Rails 8's generated `bin/docker-entrypoint`
runs `db:prepare` — *not verified today, from prior knowledge*) or through `kamal app exec`.

Steward declares `release` as argv, runs it from the new image **before the new colour
starts**, and fails safe — nothing written, nothing started, the old colour still serving.

*This is a place Steward is genuinely ahead, and it is ahead **because** of a restriction.*
Having refused `exec`, it had to make the release step declarative — and a declared step that
is covered by the spec digest and cannot half-deploy is better than a shell command run by
hand. The constraint produced the better feature.

## Where Kamal is clearly ahead

Stated without hedging, because an audit that only finds the other tool wanting is not an
audit:

- **Multi-server roles.** `servers:` with `web:` / `job:` roles does two things at once:
  it runs a worker, and it puts that worker on different hosts. The **worker half is now
  answered** (`processes`, above); the **hosts half is not** — a Steward process runs
  wherever its app is placed, and there is no way to say *this worker, on that box*.
  Whether that matters depends on whether anyone wants a worker fleet separate from a web
  fleet, which the placement layer could express as two installs but the process field
  cannot.
- **A deploy lock.** `kamal lock` prevents two people deploying at once. Steward's only lock
  is a flock on the Record for sequence integrity — two concurrent deploys of one app would
  both proceed and race on colours and unit files. **A real hazard, cheap to fix.**
- **It builds.** `builder:` produces and pushes the image. Steward starts from a digest and
  says building is not its job — defensible, but it is a step the operator still owns.
- **Ergonomics.** Aliases, `kamal console`, `kamal dbc`, one file in the repo. Steward asks
  for more setup before the first deploy.

## What to take

1. ~~**A deploy lock.**~~ **Taken 2026-08-20.** Every verb that writes an app's state now
   holds an exclusive flock on `apps/<name>.lock` first
   ([`blueprint/steward/deploy.md`](../../blueprint/steward/deploy.md), *One Act on an App
   at a Time*). Per app rather than per box, so a slow release step blocks only its own
   app; refused rather than queued, and refused before the record, because nothing was
   attempted. One thing fell out in our favour: flock dies with the process, so unlike
   `kamal lock` there is no `unlock` verb to ship and no stale marker for anyone to
   adjudicate.
2. **Reconsider accessory lifecycle** — see below.
3. ~~**Roles / a worker process.**~~ **Taken 2026-08-20**, and the open question settled
   the other way from Kamal's. Kamal's roles are *(hosts, cmd)* and each is deployed on its
   own; Steward's `processes` are a field on one spec, inheriting image, env, secrets and
   volumes, flipping with the app's colours. The deciding argument was skew: a worker that
   can be deployed separately can land on a different digest from the web process, and a
   worker running yesterday's code against today's enqueued jobs is a failure the record
   could not describe. One spec, one digest, one deploy. See
   [`blueprint/steward/deploy.md`](../../blueprint/steward/deploy.md), *Processes*.
   **Multi-server roles remain out** — placement across boxes is still N recorded acts, and
   nothing here changes that.
4. **Nothing on hooks.** Kamal's hooks run on the deploying machine (*inferred from
   `.kamal/hooks/` living in the repo; the docs do not say so outright*), which is harmless.
   A hook **on the box** is the ambient-authority shape Steward already refused.

## Newly open

**Should an accessory upgrade ride the app's deploy?** Steward says yes — one spec, one
digest, one deploy, and the digest covering the database's image is a property worth having.
Kamal says no, and for a database that is a good instinct: a web deploy should not restart
Postgres. The mitigation already in place (an unchanged unit is left alone) means it only
happens when the accessory genuinely changed — but *changing the Postgres image* and
*shipping the app* then become the same act, with no way to stage one without the other.

An `accessories`-only apply, or leaving a changed accessory declared-but-not-applied until
asked, are both possible. Neither is obviously right, and it interacts with the spec digest:
if the accessory can lag the spec, the digest no longer describes what is running, which is
the property the whole design leans on.
