require "test_helper"

# The merge of the two records into one timeline shape (decisions/two-records.md):
# Steward Console's own acts are authored; box entries are witnessed unless our own
# client issued them.
class ChainItemTest < ActiveSupport::TestCase
  test "a Steward Console event becomes an authored item" do
    e = Event.new(at: Time.current, actor: "alice@x", action: "added",
                  summary: "Added label env=prod on box")
    i = ChainItem.from_event(e)
    assert_equal :authored, i.origin
    refute i.witnessed?
    assert_equal "Added label env=prod on box", i.summary
    assert_equal "alice@x", i.actor
  end

  test "a box entry by our own client is authored; anyone else is witnessed" do
    entry = { "time" => "2026-06-10T00:00:00Z", "actor" => "console",
              "action" => "deploy", "args" => [ "app1" ] }

    mine = ChainItem.from_record_entry(entry, client: "console")
    assert_equal :authored, mine.origin
    assert_equal "deploy app1", mine.summary

    theirs = ChainItem.from_record_entry(entry.merge("actor" => "ci"), client: "console")
    assert_equal :witnessed, theirs.origin
    assert theirs.witnessed?
  end

  # The two streams: acts are the chain, status is a sample series. One rule
  # judges both records, so a box's timer entry is dropped like our own.
  test "a status sample is not an act, from either record" do
    box = ChainItem.from_record_entry(
      { "time" => "2026-06-10T00:00:00Z", "actor" => "snapshot.timer", "action" => "observe" },
      client: "console")
    assert box.status?

    own = ChainItem.from_event(Event.new(at: Time.current, actor: "snapshot.timer",
                                         action: "observed", summary: "Status sample ingested"))
    assert own.status?

    act = ChainItem.from_event(Event.new(at: Time.current, actor: "alice", action: "deployed"))
    refute act.status?
  end
end
