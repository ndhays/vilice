# Upgrading is install, then prepare

> Decided with the ceiling ([`ceiling-is-the-machine.md`](ceiling-is-the-machine.md)) and
> written down 2026-10-03, when the first upgrade raised the question. The steps are in
> [`blueprint/vilice/provision.md`](../blueprint/vilice/provision.md).

## The question

Every tool of this kind has an `upgrade` command. Vilice does not, and the first person to
upgrade a box will ask why.

## The decision

**There is no `vilice upgrade`.** An upgrade is the two steps a first install already is,
run as root on the box:

```bash
curl -fsSL https://get.vilice.org/install.sh | sudo bash -s -- <version>
sudo vilice prepare <role>
```

`install.sh` verifies the release against a key from a different provider and replaces
the binary. `prepare` approves the new binary and converges whatever the version added.
The installer ends by printing the second line, with the box's own role, so the step is
not left to memory.

## Why

- **The gate must not be able to replace the gate.** Everything Vilice claims rests on
  there being no path around it. A verb that swaps the binary is such a path, so the
  binary is root-owned and nothing Vilice runs as can write it. Replacing Vilice stays
  *below* Vilice.
- **An upgrade needs root anyway, and that is the tamper check working.** `prepare`
  records the binary's digest, and every verb refuses a binary that does not match it
  ([`roles-not-packs.md`](roles-not-packs.md)). A new version *is* a changed binary until
  root says otherwise. So approval cannot be skipped, and a command that hid it would be
  hiding the one step that makes a swapped binary detectable.
- **The verifier stays outside the thing being verified.** `install.sh` is fetched fresh
  and the key comes from another provider. A self-upgrade would have the *old* binary
  judge the new one, and if the old one is what went wrong, that judgement is worth
  nothing.
- **One copy of the dangerous code.** Download, verify, install is the most
  security-sensitive logic in the project. It lives in `install.sh`, about a hundred lines a
  reader can audit. An `upgrade` verb would put a second copy in Go, to be kept in step.

## What it costs

- **Two commands, not one.** They fit on a line, joined by `&&`.
- **Between the two, Vilice refuses to act.** With the new binary on disk and not yet
  approved, every verb that acts on apps or reads their state refuses. What still runs is
  what an operator needs to inspect and repair the box: the root commands, and
  `authorize`, `revoke`, `verify`, `record` and `actors`. That is the check doing its
  job, but it is a window: a scoped deploy arriving in it fails. Apps are not affected —
  they are ordinary units under systemd and Vilice is not a daemon.

## Roads not taken

- **`vilice upgrade` over a scoped key.** A key that can replace the gate holds every
  scope at once, whatever its line in the ledger says.
- **A root-only `vilice upgrade <version>`**, wrapping the two steps. No new path, since
  it would sit at the ceiling beside `prepare`. Declined for the last two reasons above:
  the old binary would verify its own successor, and the verify logic would exist twice.
  The installer's closing hint gets most of the convenience without either.
- **Unattended upgrades of Vilice itself**, on a timer. A box that changes its own gate
  with nobody present is the opposite of an accountable act; OS security patches are
  different in kind, and `harden` already schedules those.
- **An apt package.** Still open ([`open/vilice-open-questions.md`](open/vilice-open-questions.md)):
  apt would put the bits on disk, and `prepare` would stay the accountable act that turns
  them on — the same two steps, with apt standing in for `install.sh`.
