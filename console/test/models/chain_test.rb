require "test_helper"

# One box's timeline from the two records — shapes taken from a real box's record.
class ChainTest < ActiveSupport::TestCase
  def entry(seq, time, action, args = [], actor: "operator", scope: "root")
    { "seq" => seq, "time" => time, "actor" => actor, "scope" => scope,
      "action" => action, "args" => args }
  end

  test "a prepare run is one command, with its steps folded under it" do
    entries = [
      entry(48, "2026-09-30T18:23:46Z", "prepare", %w[host --yes]),
      entry(49, "2026-09-30T18:23:47Z", "prepare-role", %w[host]),
      entry(50, "2026-09-30T18:23:47Z", "authorize-binary", %w[sha256:4a214b688bcb22226668653c9723e06a5b576df01fb6af9a48a6d8d3accb4f6f])
    ]
    items = Chain.for_machine([], entries, client: "console")
    assert_equal 1, items.size
    assert_equal "steward prepare host --yes", items.first.command
    assert_equal [ "role set to host", "binary authorized sha256:4a2…cb4f6f" ], items.first.steps.map(&:summary)
  end

  test "a step is never drawn as a command someone ran" do
    item = ChainItem.from_record_entry(entry(49, "2026-09-30T18:23:47Z", "prepare-role", %w[host]), client: "console")
    assert item.step?
    assert_nil item.command
    assert_nil item.via
  end

  test "a refusal reads as the verb that was refused, and a minute-by-minute run is one line" do
    entries = (0..39).map do |i|
      entry(10 + i, (Time.utc(2026, 9, 29, 12) + i.minutes).iso8601, "binary-unrecognized", %w[snapshot], scope: "deny")
    end
    items = Chain.for_machine([], entries, client: "console")
    assert_equal 1, items.size
    refusal = items.first
    assert refusal.refusal?
    assert_equal "snapshot — binary unrecognized", refusal.summary
    assert_equal "steward snapshot", refusal.command
    assert_nil refusal.via # nothing ran, so no stamp
    assert_equal 40, refusal.repeats
  end

  test "an act this console sent is one line: the event, carrying the box's entry" do
    at = Time.utc(2026, 9, 29, 16)
    event = Event.create!(at: at, actor: "operator@console.test", action: "removed",
                          summary: "hello from nick-main", outcome: "pending",
                          raw: { command: "remove hello --json" })
    event.settle!("failed", detail: "podman: no such app")
    box = entry(40, (at + 3.seconds).iso8601, "remove", %w[hello], actor: "console", scope: "operate")

    items = Chain.for_machine([ event ], [ box ], client: "console")
    assert_equal 1, items.size
    assert_equal "operator@console.test", items.first.actor # the person, not the key
    assert_equal "failed", items.first.outcome
    assert_equal 40, items.first.box_entry["seq"]
  end

  test "our key's entry with no event to match still shows" do
    box = entry(41, "2026-09-29T16:00:00Z", "restart", %w[web], actor: "console", scope: "operate")
    items = Chain.for_machine([], [ box ], client: "console")
    assert_equal [ "steward restart web" ], items.map(&:command)
  end
end
