# A sample is not an act, so it stays out of the chain

> Decided 2026-08-11. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The problem

The record is two streams — discrete acts (`Event`) and continuous health (`Snapshot`) —
under the rule *show acts always; show status only at transitions*. Nothing enforced it,
and the head of the Status chain read "Status sample ingested". At any real snapshot
cadence the chain becomes a polling log.

## The decision

**A sample reports that we looked; an act reports that something happened. Only acts are
chain rows.**

- `Event::STATUS_ACTIONS` names the sample verbs — both spellings, since the console
  writes `observed` and a box entry says `observe`.
- `Event.acts` excludes them, and every chain the UI renders goes through it.
- `ChainItem#status?` applies the same constant to box-record entries.

**Nothing is deleted.** This is a display rule, not a retention one. The seeds also
stopped fabricating status `Event`s, which no app code ever wrote; `Vilice::Fake` still
emits an `observe` entry, because a real box record contains them.

## Roads not taken

- **Filter in the view.** Every chain would need to remember, and the one that forgot
  would be the regression. The rule lives in one constant.
- **Reuse the `event_kind` heuristic** (`application_helper.rb`). It is a substring guess
  tuned for colour. Filtering wants an exact list, and a styling heuristic that starts
  deciding what is visible breaks quietly.
- **Delete status events, or stop recording samples.** The record is append-only, and the
  series is wanted once ingestion lands.
- **Fake transitions now** by diffing the last two live reads. It invents a series that
  is not stored and would disagree with the real one.
- **A `kind` column on `events`.** A migration to encode what the verb already says.
  Revisit if actions outgrow a small list.

## Still open

Transitions ("went critical 03:12") are not built. `Snapshot` has a table and nothing
writes it, so there is no series to derive one from. Blocked on ingestion (#6 in
[`open/ui-roadmap.md`](open/ui-roadmap.md)).
