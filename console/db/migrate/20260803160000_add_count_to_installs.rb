# The intention layer's missing half (decisions/drift-is-surfaced-never-closed.md).
#
# An Install already knew where it *had been placed* — one InstallTarget per box. It did
# not know how many boxes were *asked for*, so "intention: 3 · reality: 2" had no
# left-hand side and drift in placement could not be stated, only in image.
#
# `count` is that left-hand side: the number of boxes this app should serve from. It is a
# claim, never a fact — nothing reconciles it, and the gap it opens is closed by a named
# act or not at all.
class AddCountToInstalls < ActiveRecord::Migration[8.1]
  def change
    # Default 1: every existing install asked for exactly the one box it sits on, so the
    # backfill is the default and no data migration is needed.
    add_column :installs, :count, :integer, null: false, default: 1
  end
end
