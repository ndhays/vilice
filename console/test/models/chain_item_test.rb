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

  # The record's lower levels: the exact command, the reply, and the entry as stored.
  test "an event carries the command it sent and the reply it got" do
    e = Event.create!(at: Time.current, actor: "alice@x", action: "updated",
                      outcome: "pending", raw: { command: "apply-updates --json" })
    e.settle!("ok", output: { "ok" => true, "message" => "machine packages updated" })
    i = ChainItem.from_event(e)
    assert_equal "steward apply-updates --json", i.command
    assert_equal "machine packages updated", i.output["message"]
    assert_equal "apply-updates --json", i.entry["command"]
    refute i.entry.key?("output")                  # shown once, under Output
  end

  test "an act recorded here that sent nothing to a box has no command" do
    i = ChainItem.from_event(Event.new(at: Time.current, actor: "alice@x", action: "labelled"))
    assert_nil i.command
  end

  test "a box entry's command is its verb and arguments, read straight off the entry" do
    entry = { "time" => "2026-06-10T00:00:00Z", "actor" => "ci", "action" => "deploy", "args" => [ "app1" ] }
    i = ChainItem.from_record_entry(entry, client: "console")
    assert_equal "steward deploy app1", i.command
    assert_equal entry, i.entry
  end

  # The stamp shows the door an act came through.
  test "an act's door: this console, the box's own shell, or another key" do
    sent = Event.new(at: Time.current, actor: "alice@x", action: "updated", raw: { command: "apply-updates --json" })
    assert_equal :console, ChainItem.from_event(sent).via
    assert_equal "apply-updates", ChainItem.from_event(sent).verb

    typed = { "time" => "2026-06-10T00:00:00Z", "actor" => "operator", "action" => "restart", "args" => [ "web" ] }
    assert_equal :local, ChainItem.from_record_entry(typed, client: "console").via

    ci = typed.merge("actor" => "ci-deployer")
    assert_equal :key, ChainItem.from_record_entry(ci, client: "console").via

    ours = typed.merge("actor" => "console")
    assert_equal :console, ChainItem.from_record_entry(ours, client: "console").via

    assert_nil ChainItem.from_event(Event.new(at: Time.current, actor: "alice@x", action: "labelled")).via
  end
end
