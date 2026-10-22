# The record is drawn as a list, not as a chain

> Spec: [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The decision

**Drop the vertical rail between record entries; separate them with a hairline.**

The rail drew a relationship that does not exist. Two adjacent entries share a record,
not a cause, and a line between them reads as *this, therefore this*. It also could not
assert what is worth asserting — that the chain is unbroken — because it draws itself the
same whether the chain verifies or not. That claim belongs to the chain-integrity badge,
which can fail.

Each entry is now an inbox line: the act is the subject; who and where are the quiet
second line; when is the right-hand column.

**The rule: a row may state facts about itself; only a grouping that *is* the
relationship may draw the relationship.**

## Case is fixed at read time

Entries came from a dozen call sites in two voices — `Placed web on b2` beside `deployed
acme-web on devbox`. The record is append-only, so stored summaries cannot be rewritten.
Entries are sentence-cased in CSS. The recorded fact is untouched, and old rows come into
line. Case is not a fact.

## The same test, twice more

- **The amber glyph.** Entries whose verb "touched a box" drew amber, decided by a
  hand-kept substring list (`WITNESSED_VERBS`). The list had rotted silently: `updated`
  had fallen out, so apply-updates drew as an observe. A signal that can be wrong and
  never complain is worse than none. Colour is now spent only on a failed act and a
  running one.
- **The fleet tree under other groupings.** The Machines list indents the boxes a
  balancer fronts. Doing that under `Reachability` would assert *this box is down because
  that one is* and could send someone to the wrong box. The edge travels as a per-row
  fact (`behind edge-01`).

## Where it is

`app/views/events/_chain.html.erb` and `.chain-*` in `record.css`; `Machine#behind` and
`.behind-edge` in `machines/_row.html.erb`. `ApplicationHelper#event_kind` and
`WITNESSED_VERBS` are deleted.
