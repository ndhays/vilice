# Status is an inbox, not a feed

> Spec: [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The decision

The Status page answers one question: *is there anything I need to deal with?* Either
there is a list, or a green check and **Nothing to report**. It does not show recent
acts.

A "Latest" strip was built and removed. It showed acts already settled — things nobody
needs to act on. On a healthy fleet it turned "nothing is wrong" into a wall of text. The
Record is one click away, with filters and 200 entries.

**The empty state is the goal.** A large green check, one sentence, and the app and
machine counts underneath. The counts prove the page is empty because we looked.

`HomeController` does not load `@recent`, and a test in
`test/controllers/journeys_test.rb` asserts the page renders no chain.

## Roads not taken

- **Keep Latest, but shorter.** The problem was not the height: a settled act is not
  something to act on.
- **Show Latest only when the fleet is healthy.** Makes the calm state busier than the
  alarming one.
