# Dev/test-only stand-in for the scoped-SSH read (the bottom of app/services/steward.rb).
#
# When fake-observe is on, Steward.read returns a canned envelope built from a
# machine's `fake-health` label instead of shelling out to ssh — so a seeded
# scenario (db/seeds/) renders deterministically with no real box, no network, and
# no dependency on a reachable host. The envelopes match the real `steward
# status|record|doctor --json` shapes, so the whole observe UI lights up exactly as
# it would against a box.
#
# Off by default. Never active in production: `on?` requires both a dev/test env
# *and* the STEWARD_FAKE_OBSERVE switch.
#
#   fake-health label → what the machine reports:
#     ok      reachable, calm (default when the label is absent)
#     warn    reachable, memory/disk under pressure
#     crit    reachable, critically low + hardening drift
#     offline unreachable (read fails, like a box that's gone)
module Steward
  module Fake
    module_function

    def on?
      Rails.env.local? && ENV["STEWARD_FAKE_OBSERVE"].present?
    end

    # The {ok:, data:, at:} result Steward.read would return, per verb.
    def envelope(machine, command)
      health = health_for(machine)
      at = Time.current
      return { ok: false, error: "fake: #{machine.name} is unreachable", at: at } if health == "offline"

      data =
        case command.to_s.split.first
        when "status" then { "ok" => true, "data" => status_data(machine, health) }
        when "record" then { "ok" => true, "data" => record_data(machine) }
        when "doctor" then { "ok" => true, "data" => { "checks" => [] } }
        else { "ok" => true, "data" => {} }
        end
      { ok: true, data: data, at: at }
    end

    # ── per-verb payloads ──────────────────────────────────────────────────────

    # Percentages chosen to land each health band squarely past MachineStatus's
    # warn/crit thresholds, so the dot and narrative are unambiguous.
    BANDS = {
      "ok"   => { mem: 35, disk: 40, load: "0.20", uptime_days: 12 },
      "warn" => { mem: 84, disk: 80, load: "1.60", uptime_days: 5 },
      "crit" => { mem: 95, disk: 96, load: "7.90", uptime_days: 1 },
    }.freeze

    MEM_TOTAL_KB  = 16_000_000
    DISK_TOTAL    = 100_000_000_000

    def status_data(machine, health)
      b = BANDS.fetch(health, BANDS["ok"])
      {
        "machine" => {
          "machine_id"       => self_id_for(machine),
          "hostname"         => "#{machine.name}.fake",
          "load1"            => b[:load],
          "uptime_sec"       => b[:uptime_days] * 86_400,
          "mem_total_kb"     => MEM_TOTAL_KB,
          "mem_available_kb" => (MEM_TOTAL_KB * (100 - b[:mem]) / 100.0).round,
          "disk_total_bytes" => DISK_TOTAL,
          "disk_free_bytes"  => (DISK_TOTAL * (100 - b[:disk]) / 100.0).round,
        },
        "apps"      => apps_for(machine),
        "hardening" => hardening_for(health),
      }.tap do |d|
        (m = maintenance_for(machine, health)) and d["maintenance"] = m
        (u = updates_for(machine, health)) and d["updates"] = u
      end
    end

    # The automatic-maintenance window the box would report. Present when hardening holds
    # (unattended-upgrades on); absent on a drifted box. A `fake-maintenance` label sets
    # the time (default 04:00).
    def maintenance_for(machine, health)
      return nil if health == "crit" # hardening drift → unattended-upgrades off
      { "reboot_time" => label_value(machine, "fake-maintenance") || "04:00", "auto_reboot" => true }
    end

    # Available package updates the box would report. Driven by a `fake-updates` label (a
    # count); absent → a small default by band. Returns nil (no updates) for a count of 0.
    UPDATE_POOL = %w[
      libssl3 openssl libc6 libcurl4 sudo openssh-server tar libzstd1 libsystemd0
      libgnutls30 perl-base libpcre2-8-0 wget libexpat1 zlib1g
    ].freeze
    UPDATE_DEFAULTS = { "ok" => 0, "warn" => 4, "crit" => 9 }.freeze

    def updates_for(machine, health)
      raw = label_value(machine, "fake-updates")
      n = raw ? raw.to_i : UPDATE_DEFAULTS.fetch(health, 0)
      return nil if n <= 0
      pkgs = UPDATE_POOL.first([ n, UPDATE_POOL.size ].min)
      { "count" => n, "security" => n, "packages" => pkgs }
    end

    # The box's own (witnessed) record. The chain merge adds Steward Console's authored
    # events separately; these stand in for entries written on the box itself —
    # one under our own client (authored) so the merge shows both origins.
    def record_data(machine)
      app = machine.installs.first&.name || "app"
      client = ENV.fetch("STEWARD_CLIENT_NAME", "console")
      entries = [
        { "time" => 26.hours.ago.iso8601, "actor" => "ci-deployer",    "action" => "deploy",  "args" => [ app ] },
        { "time" => 90.minutes.ago.iso8601, "actor" => client,         "action" => "restart", "args" => [ app ] },
        { "time" => 5.minutes.ago.iso8601, "actor" => "snapshot.timer", "action" => "observe", "args" => [] },
      ]
      { "entries" => entries, "count" => entries.size, "intact" => true }
    end

    # ── helpers ────────────────────────────────────────────────────────────────

    def health_for(machine)
      label_value(machine, "fake-health") || "ok"
    end

    # Light up "you are here" when a machine is tagged fake-self and Steward Console
    # knows its own id; otherwise a stable per-machine id.
    def self_id_for(machine)
      self_id = ENV["STEWARD_SELF_MACHINE_ID"]
      return self_id if self_id.present? && label_value(machine, "fake-self")
      "fake-#{machine.id}"
    end

    def apps_for(machine)
      machine.install_targets.includes(:install).map do |t|
        { "name" => t.install.name, "image" => t.current_image || t.install.image }
      end
    end

    def hardening_for(health)
      hardened = health != "crit" # only a critical box also shows hardening drift
      MachineStatus::HARDENING.keys.index_with { hardened }
        .merge("checked_at" => 1.hour.ago.iso8601)
    end

    def label_value(machine, key)
      machine.labels.find { |l| l.key == key }&.value
    end
  end
end
