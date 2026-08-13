require "test_helper"

# The dev/test fake-observe seam: when on, Steward.read answers from a canned
# envelope built off a machine's `fake-health` label — no ssh, no box. Lets seeded
# scenarios render deterministic health. Off in production by construction.
class Steward::FakeTest < ActiveSupport::TestCase
  def with_fake
    ENV["STEWARD_FAKE_OBSERVE"] = "1"
    yield
  ensure
    ENV.delete("STEWARD_FAKE_OBSERVE")
  end

  def machine(health)
    m = Machine.create!(name: "fake-#{health || 'none'}-#{SecureRandom.hex(2)}",
                        ssh_host: "x", scope: "observe")
    m.labels.create!(key: "fake-health", value: health) if health
    m
  end

  def status_of(m)
    MachineStatus.from(Steward::Observe.status(m, refresh: true))
  end

  test "off by default — no env var, no interception" do
    refute Steward::Fake.on?
  end

  test "an ok box reads online and calm, fully hardened" do
    with_fake do
      s = status_of(machine("ok"))
      assert s.online?
      assert_equal :ok, s.health
      assert s.hardened?
    end
  end

  test "a warn box reads online but under pressure, still hardened" do
    with_fake do
      s = status_of(machine("warn"))
      assert_equal :warn, s.health
      assert s.hardened?
    end
  end

  test "a crit box reads critical and shows hardening drift" do
    with_fake do
      s = status_of(machine("crit"))
      assert_equal :crit, s.health
      refute s.hardened?
    end
  end

  test "an offline box reads unreachable" do
    with_fake do
      refute status_of(machine("offline")).online?
    end
  end

  test "an unlabelled box defaults to ok" do
    with_fake do
      assert_equal :ok, status_of(machine(nil)).health
    end
  end

  test "a fake-updates label makes the box report that many updates" do
    with_fake do
      m = machine("ok")
      m.labels.create!(key: "fake-updates", value: "3")
      s = status_of(m)
      assert s.updates_available?
      assert_equal 3, s.security_count
      assert_equal 3, s.update_packages.size
    end
  end

  test "a calm box reports no updates by default; no apply-now offered" do
    with_fake do
      assert_not status_of(machine("ok")).updates_available?
    end
  end

  test "a hardened box reports a maintenance window; a fake-maintenance label sets the time" do
    with_fake do
      assert_equal "04:00", status_of(machine("ok")).maintenance_time # default
      m = machine("warn")
      m.labels.create!(key: "fake-maintenance", value: "02:30")
      assert_equal "02:30", status_of(m).maintenance_time
    end
  end

  test "a drifted (crit) box reports no maintenance window — unattended is off" do
    with_fake do
      assert_not status_of(machine("crit")).maintenance_known?
    end
  end

  test "the box record reads back intact" do
    with_fake do
      rec = Steward::Observe.record(machine("ok"), refresh: true)
      assert rec[:ok]
      assert rec.dig(:data, "data", "intact")
    end
  end

  # The seam hooks Steward.read, which Steward::Mutate shares. Answering a mutate
  # would settle a witnessed Event as *succeeded* for an act that never reached a
  # box — a record entry asserting something that did not happen.
  test "a mutate is refused, not faked" do
    with_fake do
      result = Steward.read(machine("ok"), "deploy nginx --image ghcr.io/x@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
      assert_not result[:ok], "fake-observe answered a deploy"
      assert_match(/will not fake/, result[:error])
      assert_match(/STEWARD_FAKE_OBSERVE/, result[:error])
    end
  end

  # An act still writes its pending entry first (record before act) and then settles
  # honestly as failed — the invariant holds, and the reason is on the entry.
  test "a refused mutate settles its Event as failed rather than ok" do
    with_fake do
      m = machine("ok")
      m.update_columns(scope: "operate")
      assert_difference -> { Event.count }, 1 do
        Steward::Mutate.run(m, "restart nginx", actor: "alice", action: "restarted")
      end
      assert_equal "failed", Event.latest.first.outcome
    end
  end

  # `actors` is a read, but this seam does not model a rights ledger. Inventing an
  # empty one would render as "nobody has access", the dangerous misreading the
  # Access page exists to prevent.
  test "a read it does not model is refused rather than answered empty" do
    with_fake do
      result = Steward::Observe.actors(machine("ok"), refresh: true)
      assert_not result[:ok]
    end
  end
end
