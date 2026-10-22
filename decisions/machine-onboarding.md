# Machine onboarding — the console is never root

> Flows still ahead (Create Machine): [`open/create-machine.md`](open/create-machine.md).
> The operator's journey: [`blueprint/console/journeys.md`](../blueprint/console/journeys.md).

## The bootstrap needs root, and no key has it

Taking a box from bare to Vilice-ready needs OS root: install the binary, `apt` the
dependencies, create `_vilice`, lay the record floor, write the sudoers grant. All three
scopes run as `_vilice` behind forced commands. Even `grant` cannot `apt install`, create
users, write `/etc`, or run `prepare`/`harden`.

**That gap is the guarantee.** If the console could turn a bare box into its own
controlled box with no local root step, there would be a path to the box's root power
that skips a local, witnessed action.

## The decision

The root bootstrap is done **locally**. The only thing handed to the console is a scoped
key authorized during it. The console generates the keypair (private half encrypted at
rest — [`data-model.md`](../blueprint/console/data-model.md)); the public half goes into
the bootstrap's `authorize` line. **The console's key is born scoped; it never holds
root, even briefly.**

The bootstrap arrives one of three ways — a pre-baked image, cloud-init at server-create,
or a one-time manual root session — each ending in the same `authorize` line. `harden`
then closes root SSH once a keyed login account exists.

## Road not taken

**The console holds a transient root key, then removes or demotes it.** A transient root
key is still a path from the control plane to the box's root power. See
[`ceiling-is-the-machine.md`](ceiling-is-the-machine.md).
