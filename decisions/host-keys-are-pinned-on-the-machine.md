# A box's host key is pinned on its Machine, and replacing it is an act

> Decided 2026-10-22. Code: `console/app/services/host_key.rb`, `Vilice.ssh`,
> `Machines::HostKeysController`. Settles "Host keys — whose memory, and who forgets" in
> [`open/console-open-questions.md`](open/console-open-questions.md).

## What happened

The first deployed console met a rebuilt box. ssh refused it — rightly — and the console
said to run `ssh-keygen -R` "as the user the console runs as". That user is inside a
container, and Vilice has no shell into one. The only way through was redeploying the
console, which forgot *every* box's key at once and trusted them all again on next
contact. The memory was a file outside the database: not backed up, gone on each
redeploy, and nothing recorded what it trusted.

## The decision

- **The host key lives on the Machine** (`ssh_host_key`, `ssh_host_key_trusted_at`).
  Every ssh call is given a `known_hosts` file holding that one key and nothing else —
  never the console user's own files — with `StrictHostKeyChecking=yes`.
- **A box with none is trusted on first contact, and pinned only if the call got
  through.** "Got through" means the box accepted the key it authorized. Public-key
  authentication signs data bound to that connection, so a machine in the middle cannot
  relay it to the real box; a key pinned this way is the key of the box that holds our
  authorized key. A mistyped address answers, but does not authenticate, and pins
  nothing. Pinning is recorded: `trusted host key`, with the fingerprint.
- **A different key is refused, and only a person replaces it.** Machine Settings → *The
  box's key* compares what Vilice trusts with what the box answers now (`ssh-keyscan`),
  fingerprint beside fingerprint, with a warning that a change is also what an attacker
  looks like and the command to check on the box itself. *Trust the new key* asks the
  box again and refuses if the answer differs from the fingerprint the person was shown.
  It is recorded with both fingerprints.
- **Not a ceremony act.** It runs nothing on the box; it changes what the console will
  accept from it. So it is an own-record act, like transferring a machine.

## Roads not taken

- **Keep `known_hosts` on the storage volume.** It would survive a redeploy, and still
  be a file outside the database that nothing records and only a shell can edit.
- **Confirm the first key by hand,** shown beside the authorize line. The operator is on
  the box then and could read it — but authenticated first contact already proves the
  same thing, with no step to skip or rubber-stamp.
- **Trust the new key automatically after a rebuild.** A rebuild and an attack look the
  same from here. That is the one decision only a person can make.
- **`ssh-keyscan` at onboarding.** An unauthenticated read: it would pin whatever answered
  the address first, which is weaker than waiting for the first call that authenticates.

## What it does not do

It does not check a box's key against anything outside the console — DNS SSHFP records,
a provider's API. The *Trust the new key* page gives the command to read it on the box;
following it is up to the person pressing the button.
