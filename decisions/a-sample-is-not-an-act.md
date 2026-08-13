# A sample is not an act, so it stays out of the chain

Decided 2026-08-11. The canonical rule now lives in
[`blueprint/console/interface.md`](../blueprint/console/interface.md); this records the
*why* and what was rejected.

## The question

[`interface.md`](../blueprint/console/interface.md) has always said the record is **two
streams** — discrete acts (`Event`, the spine) and continuous health (`Snapshot`) — under
the rule *show acts always; show status only at transitions*. Nothing enforced it.

It surfaced on a running console. The Status page head-of-chain read:

```
1. Status sample ingested
   snapshot.timer · devbox · 10 minutes ago
```

The newest thing on the fleet's front page was a timer reporting that it had looked. On a
one-machine demo that costs one of six slots. At any real snapshot cadence, routine
observations are *the whole page* — the spine becomes a polling log, and "calm by default,
lead with exceptions" fails on the one screen it was written for.

## The decision

**A sample reports that we looked; an act reports that something happened. Only acts are
chain rows.**

One definition covers both records, because both can carry samples:

- `Event::STATUS_ACTIONS` names the sample verbs — both spellings, since Steward Console
  writes `observed` and a box record entry says `observe`.
- `Event.acts` excludes them, and every chain the UI renders goes through it: Status,
  the Record destination, and the per-machine merge.
- `ChainItem#status?` applies the *same* constant to box-record entries, which arrive as
  values rather than rows. A box's own timer is dropped exactly like ours.

**Nothing is deleted.** The samples remain recorded and countable; they are simply not
chain rows. The append-only guarantee is untouched — this is a display rule, not a
retention one.

Alongside it, the seeds stopped fabricating a row shape production never creates. No app
code has ever written a status `Event`; only `db/seeds/*` did, which is how the confusion
got on screen in the first place. `Steward::Fake` still emits an `observe` entry, because a
real box record genuinely contains them — it now exercises the reject path.

## What this does *not* settle

The **transitions** half — "went critical 03:12", "recovered 03:40" — is not built, and
saying so is the honest position rather than shipping a stand-in. It is blocked on a real
dependency: `Snapshot` is declared, has a table, and **nothing writes it**. Machine health
is read live and cached, never persisted, so there is no series from which a transition
could be derived. That arrives with ingestion (#6 in
[`open/ui-roadmap.md`](open/ui-roadmap.md)). Until then a health change shows on the
machine, not in the timeline.

## Roads not taken

- **Leave it and filter in the view.** Rejected: every chain would need to remember, and
  the one that forgot would be the regression. The rule belongs where the record is
  defined, in one constant two call sites share.
- **Reuse the existing `event_kind` heuristic** (`application_helper.rb`), which already
  sorts entries into `:mutate` / `:observe` for styling. Rejected: it is a substring guess
  over a verb allowlist, tuned for *colour*. Load-bearing filtering wants an exact,
  enumerable list — and a styling heuristic that silently starts deciding what is visible
  is the kind of coupling that breaks quietly.
- **Delete status events, or stop recording samples entirely.** Rejected: the record is
  append-only, and once ingestion lands the series is genuinely wanted. The problem was
  never that samples exist — it is that they were being *rendered as acts*.
- **Fake transitions now** by diffing the last two live reads. Rejected as the clever
  short-term fix over the boring long-term one: it invents a series that isn't stored, so
  it would disagree with the real one the moment #6 lands.
- **A `kind` column on `events`.** Rejected for now — a migration to encode what the verb
  already says. If actions ever grow beyond a small enumerable set, revisit.
