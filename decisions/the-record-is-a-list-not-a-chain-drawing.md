# The record is drawn as a list, not as a chain

Why the connecting rail between record entries was removed, and why the hash-chain
claim is made somewhere else.

## The question

The record *is* hash-chained. The UI drew that literally: a vertical rail linking every
entry's dot to the next, top to bottom. Should the drawing keep saying so?

## The decision

**No — drop the rail; separate entries with a hairline.** The rail drew a relationship
that does not exist between the things it joined. Two adjacent entries share a record,
not a cause: a label edit on one project and a deploy on another client's box are
neighbours by clock and nothing else. A line between them reads as *this, then
therefore this*, which is a claim the record never makes.

Worse, it spent the strongest visual device on the page — a continuous line — on the
one thing that is *never* in question. Nobody doubts the entries are in one list; they
can see the list. What is worth asserting is that the chain is **unbroken**, and a
decorative rail cannot assert that, because it draws itself identically whether the
chain verifies or not.

That claim belongs to the chain-integrity badge (`✓ record intact · N entries ·
unbroken since prepare`), which is evidence — it can fail. Leaving the rail in place
alongside it was two statements about integrity, one of them free.

## What replaced it

An inbox line. The act is the subject and carries the weight; who did it and where it
landed are the quiet second line; when is the right-hand column. Separation is a
hairline, the way a list of unrelated things is normally separated.

## A consequence worth recording: case is fixed at read time

The entries came from a dozen call sites in two voices — `Placed web on b2` beside
`deployed acme-web on devbox`. The record is **append-only** (see
[`two-records.md`](two-records.md)), so the fix cannot be to rewrite the stored
summaries, and rewriting only the *future* ones would leave the inconsistency in place
for everything already recorded.

So entries are sentence-cased in CSS, at the point of reading. The recorded fact is
untouched; the presentation is uniform; and rows written before the rule existed come
into line for free. Where display and storage disagree about a recorded fact, display
gives way — but *case* is not a fact.

## The same argument, twice more

The rail was one instance of a general error: **drawing a claim the data doesn't
make.** Two more fell to the same test.

**The amber glyph.** Entries whose verb "touched a box" drew their glyph in the
mutate amber, decided by a hand-kept list of verb substrings (`WITNESSED_VERBS`).
Once the verb was spelled out beside the glyph, the colour was repeating what the
words already said — and the list had rotted without failing: `updated` had fallen
out of it, so apply-updates was quietly drawing as an observe. A signal that can be
wrong and never complain is worse than no signal. Colour on the record is now spent
only on the exceptional: a failed act, and an act still running.

**The fleet tree, under other groupings.** The Machines list indents the boxes a
balancer fronts beneath it. Extending that to every grouping was considered and
rejected for exactly the rail's reason: under `Reachability`, a group is "boxes that
happen to be unreachable", and drawing one under another asserts *this box is down
because that one is* — a causal claim that could send someone to fix the wrong box,
in the situation where they can least afford it. The edge travels as a **per-row
fact** instead (`behind edge-01`), which is true under every grouping because it is
about that one box.

The rule, stated once: **a row may state facts about itself; only a grouping that
*is* the relationship may draw the relationship.**

## Consequence

`app/views/events/_chain.html.erb` and the `.chain-*` rules in `record.css`;
`Machine#behind` and the `.behind-edge` marker in `machines/_row.html.erb`.
`ApplicationHelper#event_kind` and `WITNESSED_VERBS` are deleted. The canonical
description is in
[`blueprint/console/interface.md`](../blueprint/console/interface.md).
