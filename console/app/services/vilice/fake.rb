# Dev/test-only stand-in for the scoped-SSH read (the bottom of app/services/vilice.rb).
#
# When fake-observe is on, Vilice.read returns a canned envelope built from a
# machine's `fake-health` label instead of shelling out to ssh — so a seeded
# scenario (db/seeds/) renders deterministically with no real box, no network, and
# no dependency on a reachable host. The envelopes match the real `vilice
# status|record|doctor --json` shapes, so the whole observe UI lights up exactly as
# it would against a box.
#
# It fakes **reads only** (`ANSWERS` below). A mutate goes through the same
# transport, and is refused rather than answered — see the note on `ANSWERS`.
#
# Off by default. Never active in production: `on?` requires both a dev/test env
# *and* the VILICE_FAKE_OBSERVE switch.
#
#   fake-health label → what the machine reports:
#     ok      reachable, calm (default when the label is absent)
#     warn    reachable, memory/disk under pressure
#     crit    reachable, critically low + hardening drift
#     offline unreachable (read fails, like a box that's gone)
module Vilice
  module Fake
    module_function

    def on?
      Rails.env.local? && ENV["VILICE_FAKE_OBSERVE"].present?
    end

    # The read verbs this seam answers, and the whole of what it will answer.
    #
    # `VILICE_FAKE_OBSERVE` fakes *observe* — the name is the contract. But the
    # transport it hooks (`Vilice.read`) is shared with `Vilice::Mutate`, so
    # without this list a canned `ok` would come back for a deploy as well. That is
    # the one answer worse than none: `Mutate.run` would settle a witnessed Event as
    # **succeeded** for an act that never reached a box — a record entry asserting
    # something that did not happen, which is the quiet second answer this design
    # rejects everywhere else.
    #
    # So anything else is refused rather than invented. A refusal is a normal failed
    # read, so the pending Event settles honestly as failed with the reason on the
    # entry, and `actors` (which this seam does not model) reads as a ledger that
    # could not be read — never as a box where nobody has access.
    ANSWERS = %w[ status record doctor logs ].freeze

    # The {ok:, data:, at:} result Vilice.read would return, per verb.
    def envelope(machine, command)
      at   = Time.current
      verb = command.to_s.split.first

      unless ANSWERS.include?(verb)
        return { ok: false, at: at,
                 error: "fake-observe answers #{ANSWERS.join(', ')} only — it will not fake " \
                        "`#{verb}`. Unset VILICE_FAKE_OBSERVE to reach a real box." }
      end

      health = health_for(machine)
      return { ok: false, error: "fake: #{machine.name} is unreachable", at: at } if health == "offline"

      data =
        case verb
        when "status" then { "ok" => true, "data" => status_data(machine, health) }
        when "record" then { "ok" => true, "data" => record_data(machine) }
        when "doctor" then { "ok" => true, "data" => { "checks" => [] } }
        # Logs carry their text in `message`, the way the real `Result` does — a
        # passthrough command has nothing structured to put in `data`.
        when "logs"   then { "ok" => true, "message" => log_lines(command) }
        end
      { ok: true, data: data, at: at }
    end

    # ── per-verb payloads ──────────────────────────────────────────────────────

    # A plausible boot, so the logs panel has something to be in a seeded scenario.
    # Deliberately says it is fake in the first line: a demo that looks like real
    # output is the sort of screenshot that ends up in a bug report.
    def log_lines(command)
      app  = command.to_s.split[1] || "app"
      tail = command.to_s[/--tail (\d+)/, 1].to_i
      base = Time.current
      lines = [
        "[fake-observe] these lines are generated, not read from a box",
        "#{stamp(base - 46)} #{app} starting (pid 1)",
        "#{stamp(base - 45)} #{app} listening on 0.0.0.0:8080",
        "#{stamp(base - 44)} health: GET / 200 in 3ms",
        "#{stamp(base - 12)} GET /  200  11ms",
        "#{stamp(base - 11)} GET /assets/application.css  200  2ms",
        "#{stamp(base - 4)}  GET /up  200  1ms"
      ]
      # Honour the tail the caller asked for, so the control visibly does something.
      (tail.positive? ? lines.last(tail) : lines).join("\n")
    end

    def stamp(time) = time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

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
        # What the box was prepared as. A real box writes this once, at `prepare`, and
        # cannot be re-prepared into the other role — so the fake reports the flag the
        # seed set rather than letting it be toggled. Without this the whole dev fleet
        # read as "not prepared", which is a state almost no real box is in.
        "role"    => machine.balancer? ? "balancer" : "host",
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
        d["reboot"] = reboot_for(machine)
        d["backups"] = backups_for(machine, d["apps"], health)
        (c = certs_for(machine, health)) and d["certs"] = c
      end
    end

    # When each app and the record last backed up, by band: calm boxes backed up
    # overnight, a warn box has an app never backed up, a crit box's last attempt
    # failed. A `fake-backups=off` label reports no repo configured.
    def backups_for(machine, apps, health)
      return { "configured" => false, "targets" => {} } if label_value(machine, "fake-backups") == "off"
      now = Time.current
      targets = { "machine" => { "last_ok" => (now - 5.hours).iso8601 } }
      apps.each_with_index do |box_app, i|
        targets[box_app["name"]] =
          if health == "crit" && i.zero?
            { "last_ok" => (now - 3.days).iso8601, "last_failed" => (now - 2.hours).iso8601,
              "error" => "Fatal: unable to open repository: connection refused" }
          elsif health == "warn" && i.zero?
            {} # never backed up
          else
            { "last_ok" => (now - (5 + i).hours).iso8601 }
          end
      end
      { "configured" => true, "targets" => targets.reject { |_, v| v.empty? } }
    end

    # The certificate each hostname placed on this box hands out, by band: calm boxes
    # hold valid certs months out, a warn box has one close to expiry, a crit box one
    # expired. Nil when no placement here names a hostname.
    def certs_for(machine, health)
      hosts = machine.apps.filter_map(&:hostname).reject(&:blank?).uniq.sort
      return nil if hosts.empty?
      hosts.each_with_index.map do |host, i|
        days = i.zero? ? { "warn" => 9, "crit" => -2 }.fetch(health, 61) : 61
        cert = { "host" => host, "not_after" => days.days.from_now.iso8601, "issuer" => "R11" }
        days.negative? ? cert.merge("valid" => false, "error" => "x509: certificate has expired or is not yet valid") : cert.merge("valid" => true)
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

    # Whether the box owes itself a restart. A real box always answers this; the fake
    # says "no" unless a `fake-reboot` label names the packages that asked (space
    # separated), or is present with any other value.
    def reboot_for(machine)
      raw = label_value(machine, "fake-reboot")
      return { "required" => false } if raw.blank?

      { "required" => true, "packages" => raw.split.grep(/\A[a-z0-9][a-z0-9.+-]+\z/) }
    end

    # The box's own (witnessed) record. The chain merge adds Vilice Console's authored
    # events separately; these stand in for entries written on the box itself —
    # one under our own client (authored) so the merge shows both origins.
    def record_data(machine)
      app = machine.apps.first&.name || "app"
      client = ENV.fetch("VILICE_CLIENT_NAME", "console")
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

    # Light up "you are here" when a machine is tagged fake-self and Vilice Console
    # knows its own id; otherwise a stable per-machine id.
    def self_id_for(machine)
      self_id = ENV["VILICE_SELF_MACHINE_ID"]
      return self_id if self_id.present? && label_value(machine, "fake-self")
      "fake-#{machine.id}"
    end

    def apps_for(machine)
      machine.placements.includes(:app).map do |t|
        { "name" => t.app.name, "image" => t.current_image || t.app.image }
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
