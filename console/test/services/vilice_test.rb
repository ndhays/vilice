require "test_helper"

# Tier-1 contract tests: the Vilice Console → Vilice protocol, offline.
#
# These pin *what Vilice Console sends* and *how it handles the reply* without an ssh
# connection or a box — the fake transport stands in for the wire (see
# test/test_helpers/fake_vilice.rb). They are the fast inner loop; a real box
# (multipass / cloud) covers Podman, Caddy, and the record end to end.
class ViliceTest < ActiveSupport::TestCase
  def machine
    @machine ||= Machine.create!(name: "box-#{SecureRandom.hex(4)}", ssh_host: "10.0.0.1")
  end

  # ── Observe: read-only, and it parses the JSON reply ──────────────────────

  test "status issues `status --json` and returns the parsed data" do
    with_fake_vilice do |vilice|
      vilice.on("status --json", data: { "apps" => [], "ok" => true })

      res = Vilice::Observe.status(machine, refresh: true)

      assert res[:ok]
      assert_equal({ "apps" => [], "ok" => true }, res[:data])
      assert vilice.issued?("status --json"), "issued: #{vilice.commands.inspect}"
    end
  end

  test "a non-zero exit surfaces as an error, not a raise" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "denied: not permitted over scoped SSH", success: false)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      assert_match "denied", res[:error]
    end
  end

  test "an unparseable reply surfaces as an error, not a raise" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "not json at all", success: true)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      assert_match "unparseable", res[:error]
    end
  end

  # ── reached is not ok ──────────────────────────────────────────────────────
  # ssh exits 255 when *ssh itself* could not get through; any other non-zero status is
  # the remote command's own. Both are `ok: false` and they are completely different
  # problems, so `read` reports which — it is what lets a failed act say "run the
  # authorize line" instead of quoting "Permission denied (publickey)" at someone.

  test "ssh's own 255 reports that the box was never reached" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "Permission denied (publickey).", success: false, exit_status: 255)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      refute res[:reached]
    end
  end

  test "a remote non-zero means we did reach the box — it answered, badly" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "denied: not permitted over scoped SSH", success: false)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      assert res[:reached]
    end
  end

  test "a reply we could not parse still counts as reaching the box" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "not json at all", success: true)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      assert res[:reached]
    end
  end

  # A refusal from Vilice is a `Result` on stdout and a non-zero exit. Handing the
  # operator that JSON showed them our transport instead of their answer.
  test "a refusal is reported in the box's own words, not as its JSON envelope" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, success: false,
                 stdout: { "code" => "not_found", "message" => 'no running app "web"' }.to_json)

      res = Vilice::Observe.status(machine, refresh: true)

      refute res[:ok]
      assert_equal 'no running app "web"', res[:error]
    end
  end

  test "output that isn't a Result is passed through as it came" do
    with_fake_vilice do |vilice|
      vilice.on(/status/, stdout: "Permission denied (publickey).", success: false, exit_status: 255)

      assert_equal "Permission denied (publickey).",
                   Vilice::Observe.status(machine, refresh: true)[:error]
    end
  end

  # ── Mutate: records before it acts (Invariant 2) ──────────────────────────

  test "a mutation records an Event, then issues the command" do
    with_fake_vilice do |vilice|
      vilice.on(/deploy/, data: { "ok" => true })

      assert_difference -> { Event.count }, 1 do
        Vilice::Mutate.run(machine, "deploy app1 --json", actor: "alice", action: "deployed app1")
      end

      event = Event.latest.first
      assert_equal "alice", event.actor
      assert_equal "deployed app1", event.action
      assert_equal machine.id, event.machine_id
      assert vilice.issued?("deploy app1 --json")
    end
  end

  test "a mutation pipes a stdin payload to the box (the deploy envelope)" do
    with_fake_vilice do |vilice|
      vilice.on(/deploy/, data: { "ok" => true })
      envelope = %({"app":{"image":"ghcr.io/x@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca"}})

      Vilice::Mutate.run(machine, "deploy app1 --json", actor: "alice",
                          action: "deployed app1", stdin: envelope)

      assert_equal envelope, vilice.stdin_for(/deploy/), "the envelope rode stdin"
    end
  end

  test "a mutation is witnessed even when the command fails" do
    with_fake_vilice do |vilice|
      vilice.on(/deploy/, stdout: "boom: health check failed", success: false)

      assert_difference -> { Event.count }, 1 do
        res = Vilice::Mutate.run(machine, "deploy app1 --json", actor: "alice", action: "deployed app1")
        refute res[:result][:ok]
        assert_match "boom", res[:result][:error]
        # the same entry is settled failed, carrying the box's reason
        assert_equal "failed", res[:event].outcome
        assert_match "boom", res[:event].detail
      end
    end
  end

  # ── The transport is genuinely offline ────────────────────────────────────

  test "an unscripted command gets a benign empty reply and is still recorded" do
    with_fake_vilice do |vilice|
      res = Vilice::Observe.status(machine, refresh: true)

      assert res[:ok]
      assert_equal({}, res[:data])
      assert_equal 1, vilice.calls.size
      assert_equal "status --json", vilice.calls.first[:command]
    end
  end
end
