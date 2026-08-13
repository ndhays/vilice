# Status is an inbox, not a feed

Why the home page carries exceptions and nothing else, and why the "Latest" strip of
recent acts was removed after being built.

## The question

Status is the first screen after sign-in. Should it also show the head of the record —
the last handful of acts across the fleet — so the operator lands on something?

## The decision

**No.** The page answers one question: *is there anything I need to deal with?* Either
there is a list, or there is a green check and **Nothing to report**. Nothing else
belongs on it.

The Latest strip was the wrong shape for the screen it sat on. It showed acts that had
already happened and already settled — by definition, things nobody needs to do
anything about. On a healthy fleet, which is the common case and the case this page is
tuned for, it turned "nothing is wrong" into a wall of text, and the one signal worth
seeing had to compete with six rows that were only there to fill space.

The record is a destination of its own, one click away in the rail, with filters and
200 entries instead of six. It is better at being a record than a strip on another page
could be.

## The empty state is the goal, so it is drawn like one

A large green check and one sentence, centred, with the install and machine counts
underneath. The counts matter: they are the proof the page is empty **because we
looked**, not because there is nothing to look at. An empty inbox should read as an
achievement, not as a list that failed to load.

## Roads not taken

- **Keep Latest, but shorter.** Three rows instead of six is the same mistake at 50%.
  The problem was never the height; it was that a settled act is not something the
  operator has to act on, and this is the page for things they do.
- **Show Latest only when the fleet is healthy** — fill the space rather than leave it.
  That makes the calm state *busier* than the alarming one, which is backwards, and it
  teaches the operator that the page's layout is decorative rather than meaningful.

## Consequence

`HomeController` no longer loads `@recent`, and the Status page renders no chain at
all — asserted in `test/controllers/journeys_test.rb`, so a feed cannot creep back
unnoticed. The canonical description is in
[`blueprint/console/interface.md`](../blueprint/console/interface.md).
