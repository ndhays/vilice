# Machine onboarding — Vilice Console is never root

How a box goes from bare → reachable by Vilice Console, and why Vilice Console never holds root —
not even transiently. The built flows and what's still ahead (Create Machine) are in
[`decisions/open/create-machine.md`](open/create-machine.md); the operator-facing
journey is in [`blueprint/console/journeys.md`](../blueprint/console/journeys.md).

## The irreducible bootstrap

Bringing a box from *bare → Vilice-ready* needs **OS root**: install the binary,
`apt` podman/caddy/restic, create the `_vilice` user, lay the accountability floor, write
the apt sudoers grant. **No Vilice scoped key can do this — by design.**

The scope ladder is `observe ⊂ operate ⊂ grant`, but **all three run as the `vilice`
user behind forced commands — none is OS root.** Even `grant` scope (the top rung:
grant/revoke, and nothing else — it is not a shell, see
[no-key-gets-a-shell.md](no-key-gets-a-shell.md)) cannot `apt install`, create users,
write `/etc`, or run `prepare`/`harden`. So the most powerful Vilice key still can't
install Vilice or prepare a box.

## Why the chicken-and-egg is the feature

That gap is **un-bypassability seen from outside**: if Vilice Console could turn a bare box
into its own controlled box with no local root step, there would be a path to the box's
root power that skips a local, witnessed action — exactly what the system forbids. The
chicken-and-egg is the guarantee, not a bug.

## The decision

The root bootstrap is done **locally**, and the only thing handed to Vilice Console is a scoped
`operate` key authorized during it. Vilice Console generates that keypair (private encrypted at
rest — [`data-model.md`](../blueprint/console/data-model.md) Decision 2); its public
half goes into the bootstrap's `authorize` line. **Vilice Console's key is born `operate`; it
never holds root, even transiently.**

The local bootstrap arrives one of three ways — pre-baked image, cloud-init/userdata at
server-create, or a one-time manual root session — each ending in the same `authorize`
line. `harden` then closes root SSH (`PermitRootLogin no`) once a keyed login account
exists, so the bootstrap's root access doesn't linger.

## Road not taken

An earlier sketch had **Vilice Console hold a transient root key, then remove or demote it**
after bootstrap. Rejected: a transient root key is still a path from the control plane to
the box's root power, however briefly — it weakens un-bypassability for convenience. There
is no Vilice Console root key to remove because there is no Vilice Console root key. Pairs with
[`ceiling-is-the-machine.md`](ceiling-is-the-machine.md) (the ceiling is the machine; every
scoped command runs as the `_vilice` user).
