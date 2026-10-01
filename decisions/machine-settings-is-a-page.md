# Machine Settings is its own page

> Decided 2026-10-01. **Supersedes** "Machine Settings is a section behind a click" in
> [`blueprint/console/interface.md`](../blueprint/console/interface.md). The page itself is
> described there.

## The question

Ownership, sharing, the key and removal sat in a collapsed section at the foot of the
machine page, below the live zones and the whole record. Two things went wrong:

- **It was too far down.** The record grows without end, so the section drifted further
  from the top with every act.
- **The one thing a new box needs was buried in it.** After registering a box by hand, the
  next step is to run the authorize line on it — and that line was inside Settings, under
  a click, at the bottom.

## The decision

**Settings gets its own page**, `/machines/:id/settings`, behind a **Settings** button
beside the labels. The machine page stays about the box: what it reports and what it can
do. And **a box Vilice has never reached leads with its authorize line**, in a Connect
panel above the live view, until the first read lands.

On the page:

- **Ownership is a sentence** — *Owned by project Acme* — because a box belongs to a
  project, and "Owner: Acme" left that unsaid.
- **Sharing saves as you pick it.** Three plainly named choices and chips for the chosen
  projects, instead of radios plus a Save button plus a separate allowlist form.
- **Transfer sits in a danger zone, closed, with nothing picked.** Releasing to no project
  is its own named option. The old picker started on "release to no one", so one press of
  Transfer could take the owner away.
- **Remove is the `revoke` command button when the console holds a grant key**: it cuts
  its own key on the box as a recorded act, then forgets the box. Below grant scope the
  console cannot revoke itself, so Remove is two steps: the line to run on the box, then
  a **Forget** button — named for what it does, not for the whole job.

## Roads not taken

- **Keep the section, move it to the top.** Fixes the distance, but puts configuration —
  and two destructive controls — above the live view, on every visit, for something
  changed rarely.
- **Revoke only by hand.** Simpler, but the console can already send any act a grant key
  allows, and showing a line to paste when a button would do the same recorded act is
  friction for its own sake.
- **A disabled `revoke` button below grant scope**, with a note. It would keep Remove
  looking like the other commands, but the console leaves out what the box would refuse
  rather than greying it out — the Operate zone and deploy follow the same rule.
- **Give the console a grant key so it can always revoke itself.** A grant key can also
  authorize *other* keys on the box: far more power than removing itself needs.
- **Always revoke before forgetting.** A box that is gone cannot answer, and refusing to
  forget it would leave a dead box in the fleet forever. *Forget without revoking* stays.

## Still open

[`projects/show`](../console/app/views/projects/show.html.erb) still uses the collapsed
section (`.page-settings`) for project details and deletion. If this page reads well, the
project's settings should follow the same shape.
