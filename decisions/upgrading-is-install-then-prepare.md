# Upgrading is install, then prepare

> Written down 2026-10-03. Steps:
> [`blueprint/vilice/provision.md`](../blueprint/vilice/provision.md).

## The decision

**There is no `vilice upgrade`.** An upgrade is the two steps of a first install, as
root:

```bash
curl -fsSL https://get.vilice.org/install.sh | sudo bash -s -- <version>
sudo vilice prepare <role>
```

`install.sh` verifies the release and replaces the binary. `prepare` approves the new
binary and converges whatever the version added. The installer ends by printing the
second line with the box's own role.

## Why

- **The gate must not be able to replace the gate.** A verb that swaps the binary is a
  path around it. The binary is root-owned and nothing Vilice runs as can write it.
- **Approval cannot be skipped.** `prepare` records the binary's digest and every verb
  refuses a binary that does not match
  ([`roles-not-packs.md`](roles-not-packs.md)). A new version is a changed binary until
  root says otherwise. A command that hid that would hide the step that makes a swapped
  binary detectable.
- **The verifier stays outside the thing verified.** `install.sh` is fetched fresh and
  the key comes from another provider. A self-upgrade has the old binary judge the new
  one.
- **One copy of the dangerous code.** Download, verify, install lives in `install.sh`,
  about a hundred lines.

## What it costs

- Two commands, joined by `&&`.
- **Between the two, Vilice refuses to act.** Verbs that act on apps or read their state
  refuse; the root commands and `authorize`, `revoke`, `verify`, `record`, `actors` still
  run. A scoped deploy arriving in that window fails. Apps are unaffected.

## Roads not taken

- **`vilice upgrade` over a scoped key.** A key that can replace the gate holds every
  scope.
- **A root-only `vilice upgrade <version>`** wrapping the two steps. No new path, but the
  old binary would verify its successor and the verify logic would exist twice.
- **Unattended upgrades of Vilice.** A box that changes its own gate with nobody present
  is not an accountable act. OS security patches are different, and `harden` schedules
  those.
- **An apt package.** Still open
  ([`open/vilice-open-questions.md`](open/vilice-open-questions.md)): apt would place the
  bits and `prepare` would still be the accountable step.
