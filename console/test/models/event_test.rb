require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "the record is append-only — no edit or delete through the app" do
    e = Event.record!(actor: "alice", action: "did a thing")
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.update!(action: "rewritten") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.destroy }
  end

  test "deleting a machine clears the link but keeps the human-readable record" do
    m = Machine.create!(name: "box-#{SecureRandom.hex(3)}", ssh_host: "1.1.1.1")
    e = Event.record!(actor: "alice", action: "deployed", machine: m, summary: "deployed on the box")
    m.destroy # dependent: :nullify uses update_all, bypassing the guard
    assert_nil e.reload.machine_id
    assert_equal "deployed on the box", e.summary
  end

  test "a pending act settles its outcome once, on the same entry" do
    e = Event.record!(actor: "alice", action: "deployed", outcome: "pending")
    e.settle!("ok")
    assert_equal "ok", e.reload.outcome
    assert e.finished_at.present?
    assert e.settled?
    # a second settle is a rewrite — refused
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.settle!("failed") }
  end

  test "settling never lets a recorded fact change" do
    e = Event.record!(actor: "alice", action: "deployed", outcome: "pending")
    e.action = "rewritten"
    e.outcome = "ok"
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.save! }
  end

  test "an instantaneous act has no outcome and stays fully append-only" do
    e = Event.record!(actor: "alice", action: "labelled")
    assert_nil e.outcome
    refute e.pending?
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.settle!("ok") } # nothing to settle
  end

  test "search narrows by actor / action / target selectors and free text" do
    box   = Machine.create!(name: "this-box", ssh_host: "2.2.2.2")
    other = Machine.create!(name: "other-box", ssh_host: "3.3.3.3")
    a = Event.record!(actor: "alice", action: "deployed", machine: box, summary: "deployed nginx")
    b = Event.record!(actor: "ci-deployer", action: "rolled back", machine: box)
    c = Event.record!(actor: "alice", action: "deployed", machine: other)

    assert_equal [ a, c ].sort, Event.search("actor=alice").sort
    assert_equal [ a, c ].sort, Event.search("action=deploy").sort   # substring
    assert_equal [ a, b ].sort, Event.search("target=this-box").sort # by machine name
    assert_equal [ a ],         Event.search("actor=alice target=this-box") # ANDed
    assert_equal [ a ],         Event.search("nginx")                # free text on summary
    assert_equal Event.all.sort, Event.search("").sort               # blank = everything
  end

  # The record is two streams (blueprint/console/interface.md): acts are the chain's
  # spine, status is a sample series. A sample reports that we looked, not that
  # anything happened, so it stays out of every chain the UI renders.
  test "acts excludes routine status samples, both spellings" do
    act = Event.record!(actor: "alice", action: "deployed", summary: "shipped api")
    Event.record!(actor: "snapshot.timer", action: "observed", summary: "Status sample ingested")
    Event.record!(actor: "snapshot.timer", action: "observe", summary: "box timer")

    assert_equal [ act ], Event.acts
    assert_equal 3, Event.count, "the samples are still recorded — only the chain drops them"
  end

  test "search is case-insensitive and AND-composes selectors with free text" do
    box = Machine.create!(name: "Prod-Box", ssh_host: "4.4.4.4")
    hit = Event.record!(actor: "Alice", action: "Deployed", machine: box, summary: "shipped api")
    Event.record!(actor: "bob", action: "deployed", summary: "shipped api")

    assert_equal [ hit ], Event.search("actor=alice target=prod api")
  end

  test "project= selects by project, and quotes let a value carry spaces" do
    acme  = Project.create!(name: "Acme Corp")
    globex = Project.create!(name: "Globex")
    a = Event.record!(actor: "alice", action: "starred", project: acme)
    Event.record!(actor: "bob", action: "starred", project: globex)

    # Without quotes the space splits the token and the filter breaks; quoted, it holds.
    assert_equal [ a ], Event.search(%(project="Acme Corp"))
    # The scope stays visible and AND-composes with more filters.
    assert_equal [ a ], Event.search(%(project="Acme Corp" actor=alice))
    assert_empty Event.search(%(project="Acme Corp" actor=bob))
  end
end
