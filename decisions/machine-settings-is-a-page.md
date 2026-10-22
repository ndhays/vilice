# Machine Settings is its own page

> Decided 2026-10-01. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The problem

Ownership, sharing, the key and removal sat in a collapsed section at the foot of the
machine page, below a record that grows without end. And the one thing a new box needs —
its authorize line — was inside it.

## The decision

**Settings is `/machines/:id/settings`**, behind a Settings button beside the facts.
**A box never reached leads with its authorize line**, in a Connect panel above the live
view, until the first read lands.

- **Ownership is a sentence** — *Owned by project Acme*.
- **Sharing saves as you pick it.** Three named choices and chips for chosen projects.
- **Transfer sits in a closed danger zone with nothing picked.** Release is its own named
  option. The old picker started on "release to no one", so one press could remove the
  owner.
- **Remove is the `revoke` command button when the console holds a grant key:** it cuts
  its own key on the box as a recorded act, then forgets the box. Below grant scope,
  Remove is two steps: the line to run on the box, then **Forget**.

## Roads not taken

- **Keep the section, move it to the top.** Puts rarely changed configuration and two
  destructive controls above the live view.
- **Revoke only by hand.** Friction, when a button does the same recorded act.
- **A disabled `revoke` button below grant scope.** The console leaves out what the box
  would refuse rather than greying it out.
- **Give the console a grant key so it can always revoke itself.** A grant key can also
  authorize other keys — far more power than removing itself needs.
- **Always revoke before forgetting.** A box that is gone cannot answer, and would stay
  in the fleet forever. *Forget without revoking* stays.

## Still open

[`projects/show`](../console/app/views/projects/show.html.erb) still uses the collapsed
section (`.page-settings`). It should follow this shape if this page reads well.
