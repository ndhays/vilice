# The Install is the app-actions home

**Status:** decided 2026-06-13; revised 2026-06-14 (machine page read-only for apps);
**partly superseded 2026-08-03** by the core/pack layering
([`core-and-packs.md`](core-and-packs.md)) — the machine page *does* now act on apps.
See "What changed" at the bottom. Refines [open/ui-roadmap.md](open/ui-roadmap.md)
§"a view shows what it's FOR".

## Decision

App lifecycle acts — deploy, roll back, start/stop/restart, remove — happen **only
from the Install, in its project context.** The Install is the root domain object
(it *is* the deploy spec, `Install#deploy_envelope`); a user manages an *app*
there: "redeploy my app", "roll it back". For the common single-target install the
box is implied; for replicas you act per target.

The **Machine page lists its apps read-only** — each app links to its Install, with
the project it serves — and carries only **machine-level** acts (e.g. apply OS
updates). It is the box lens (what's running here), not a place to act on apps.

## Why

Steward is machine-centric by nature; surfacing app acts on the machine page let
that model leak up into Steward Console's UI. The operator lives in **app + hostname +
is-it-green** and treats the machine as plumbing — they should never have to find
the box their app runs on to manage it. One home for app lifecycle (the project's
Install) keeps the mental model single and the witnessed ceremony in one place;
the machine page stays a clean read-only view of what the box runs.

**Why the revision:** the first cut kept the same verbs on the machine page as a
"sysadmin lens" (two entry points, one shared `installs/_acts` partial). In use
that was redundant — two places to do the same act, against a model that wants a
single home — so the machine page dropped the verbs and became a read-only app
list. App acts now run only with `from: "install"`.

## Mechanism (no new ceremony)

The witnessed ceremony is unchanged and still keyed to a machine (the SSH target);
its `from` param decides where it returns. App acts are launched only from the
Install page (`from: "install"`) via the `installs/_acts` partial; the machine page
launches only machine-level acts (apply-updates), which return to the machine. The
allowlist (`Mutation::ACTS`) and record-before-act invariant hold wherever an act
is triggered.

## Roads not taken

- *Machine page as a second "sysadmin lens" with the same app verbs.* **Tried, then
  reversed** — two entry points for one act is redundant and fights the single-home
  model. The machine page lists apps read-only instead.
- *A brand-new Install-scoped ceremony route.* Rejected — the act needs a machine
  (the SSH target) regardless; the `from` hint is enough. One ceremony, parameterized
  by where it was launched.

## What changed (2026-08-03)

The machine page now carries app acts: deploy, and remove, on the box itself. That
directly reverses the 2026-06-14 revision above — so it is worth being precise about
which part of this decision failed, because most of it did not.

**The reasoning was right; the premise moved.** The revision reversed machine-page app
verbs because *"two entry points for one act is redundant."* That was true when the
Install was the only way to deploy: the machine page offered the same act a second way,
against a model that wanted one home.

It stopped being true when Steward split into a core and verb packs. The machine view is
now the base layer — the view of one box, shaped by the packs that box reports — and it
does something the Install **cannot**: act on a box with no Project and no stored plan at
all. The Install does something the machine view cannot: place one app across several
boxes. They are not two doors to one act; they are two layers, and each has an act the
other cannot express.

**What still holds:** an operator who thinks in *app + hostname + is-it-green* should
never have to find the box to manage their app. That is why placement keeps its own home
one ring out, and why the machine view is not where you go to run a fleet. The rule the
revision was protecting — one home per mental model — survives; there are simply two
mental models, and always were.

**What is now false:** "the Machine page lists its apps read-only," and "app acts run
only with `from: \"install\"`."
