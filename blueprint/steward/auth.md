# Steward — Auth

Every action on the box is a **named actor with a declared scope** (invariant 1).
Steward carries this with scoped SSH — no token of its own, no network listener of its
own. It leans on OpenSSH, the most hardened remote-access daemon there is, and adds
only a thin gate.

**Status:** Canonical. Last touched 2026-08-02.

---

## The model

- **The key is the identity.** Which key authenticated tells you which named client
  is acting.
- **The forced command is the scope.** Each authorized key is pinned to
  `command="steward …"` with restrictions, so a key can only do what its scope allows
  — enforced at the SSH layer, before Steward runs.
- **`authorized_keys` is the rights ledger.** `cat` it and you see every actor and its
  ceiling, in plain text. Rights are declared and inspectable, not ambient — Article
  IV.

## The scope ladder

A higher scope grants the ones below it: `observe ⊂ operate ⊂ grant`.

| Scope | Grants |
|---|---|
| `observe` | read the record — `status`, `logs` |
| `operate` | deploy and lifecycle — everything in [deploy.md](deploy.md) |
| `grant` | mint and revoke keys — `authorize`, `revoke` |

**No scope is a shell.** Every key resolves to a *named command* or to nothing; a key
that sends no command is refused, at every rung. The top rung used to be called `ssh` and
handed out an interactive shell as the `steward` user, which meant that one key could act
on the box without writing a record — invariant 2 with an asterisk. That capability is
gone; see
[`no-key-gets-a-shell.md`](../../decisions/no-key-gets-a-shell.md). Keys authorized under
the old name still work: `ssh` is read as `grant`, minus the shell it used to promise.

## Granting and revoking — run as the `steward` user

`authorize`/`revoke` only edit `~steward/.ssh/authorized_keys` — steward's own rights
ledger — so they run as the unprivileged `steward` user, not root. Granting is the **top
rung of the ladder**, not a wall above it: a `grant`-scope key can run them; an `observe`
or `operate` key is pinned to its scope and cannot reach them. See
[decisions/ceiling-is-the-machine.md](../../decisions/ceiling-is-the-machine.md).

Because `grant` no longer implies a shell, it is narrow enough to *issue* — a control
plane can hold one and enroll keys without also holding the box.

| Command | Does |
|---|---|
| `steward authorize <pubkey> --client <name> --scope <observe\|operate\|grant>` | Write the pinned `authorized_keys` line for a named actor at a scope. |
| `steward revoke <client>` | Remove that actor's line. |

Revoking is removing a line. There is nothing else to chase down — no token to expire,
no session to kill.

A client is one key. `authorize` is keyed on the client name: re-authorizing an existing
client removes its old line and writes the new one in the same call. So **re-authorizing
with a new key is rotation** — a single command, no lockout window, no stale grant left
behind. Changing `--scope` for an existing client replaces it the same way.

---

## Reading the ledger — `steward actors`

`authorize` and `revoke` write `authorized_keys`; **`actors` reads it back**, at
`observe` scope. It exists because the ledger *is* the list of who may act on this box,
and until there was a verb for it the only way to see that list was a shell on the box —
which no scope grants. A ledger nobody can read is a ledger nobody can check.

For each line it reports the client, the scope, the key type, the OpenSSH SHA256
fingerprint, and the forced command itself, so an operator can see the ceiling rather
than trust this description of it. The key material is not reproduced: a fingerprint
identifies a key without handing a reader something to paste elsewhere, and it is the
same string `ssh-keygen -lf` prints, so it can be compared against the key in hand.

**It also reports the lines Steward did not write.** A key added by hand carries no
forced command, so its holder reaches the box without passing the gate — the one hole
un-bypassability cannot close from inside, because it is made outside. Such lines sort
to the top and are labelled as what they are. Anything whose forced command is not
`_exec` with a client and a scope counts as unpinned too; a foreign command is not
parsed into something reassuring.

A read, so it is not recorded, holds no privilege, and changes nothing.

## The forced-command wrapper is the boundary

With no network API, the forced command plus Steward's own check of its arguments is
the entire gate between an authorized key and the box. It must:

- **refuse anything outside the key's scope** — an `observe` key cannot deploy;
- **never run a client-supplied command** — read `SSH_ORIGINAL_COMMAND` only as named
  arguments, and validate them;
- **deny pty, agent, and port forwarding** — `restrict`, at every scope, no exception.

This wrapper is the first thing to audit. The classic forced-command failures —
argument injection, escaping through options, forwarding leaks — all land here.

**One door, for real.** The forced command (`_exec`) and the local CLI both reach a
command through the same function — `enter` in `internal/core/dispatch.go` — which applies the account
gate and then dispatches. They used to be two paths, and only one had the gate: `sudo
steward deploy` was refused while `sudo steward _exec --scope operate` was not, which is
the ghost install [`one-steward-per-box.md`](../../decisions/one-steward-per-box.md)
exists to prevent. A second entry point is a second gate to forget, so there is one.

**A key is one line.** `authorize` accepts a single-line public key — known type, base64
blob, at most a comment — because the key text is appended after the
`command="…",restrict` options. A newline in it would write a second `authorized_keys`
line carrying no forced command and no restrictions at all. See
[`rendered-config-is-a-boundary.md`](../../decisions/rendered-config-is-a-boundary.md).

## Where this sits in the one claim

Un-bypassability has three parts, and auth owns one of them:

- **scoped** — this file: every caller named, every right declared.
- **recorded** — [record.md](record.md): the entry is written before the action.
- **out of reach** — [provision.md](provision.md): the machine and the record no key can
  touch (the rights ledger, by contrast, is the `steward` user's own — governed by the
  ladder, not the root ceiling).

## Open

Open questions for auth are kept out of the spec, in
[`steward-open-questions.md`](../../decisions/open/steward-open-questions.md) — time-boxed
grants (`authorize --expires`), remote reach for Dispatcher, and per-action fleet
delegation. When one settles, its answer moves into this spec and its reasoning into
`decisions/`.
