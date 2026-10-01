# A read-only view over one Vilice `status --json` reply. Turns the raw record
# into the numbers — and the plain-language health line — the observe UI shows.
#
# Pure projection: it holds nothing privileged and changes nothing. This is the
# observe side of the spine made into an object (see app/services/vilice.rb).
class MachineStatus
  # Health thresholds, in percent used. Calm below warn; loud at crit.
  MEM  = { warn: 80, crit: 90 }.freeze
  DISK = { warn: 75, crit: 90 }.freeze

  LEVELS = { ok: 0, warn: 1, crit: 2, offline: 3 }.freeze

  attr_reader :error, :read_at, :raw

  # Build from a Vilice.read result: { ok:, data: <envelope>, error:, at: }.
  def self.from(result)
    new(result)
  end

  # Each hardening property the box publishes, mapped to its plain-language drift line.
  HARDENING = {
    "ssh_root_login_disabled" => "root SSH login enabled",
    "password_auth_disabled"  => "password auth enabled",
    "firewall_active"         => "firewall inactive",
    "fail2ban_active"         => "fail2ban not running",
    "unattended_upgrades"     => "unattended upgrades off",
  }.freeze

  def initialize(result)
    @ok        = !!result[:ok]
    @error     = result[:error]
    @read_at   = result[:at]
    @raw       = result[:data]
    @machine   = (result.dig(:data, "data", "machine") if @ok) || {}
    @apps      = (result.dig(:data, "data", "apps") if @ok) || []
    # The hardening fact the box published, if any. Observe reads it; it never runs
    # the check itself (that needs root on the box). Absent → "never checked".
    @hardening = (result.dig(:data, "data", "hardening") if @ok)
    # Available package updates the box reports, if any: { count, security, packages }.
    # Absent → we don't know of any (no "apply now" offered).
    @updates = (result.dig(:data, "data", "updates") if @ok) || {}
    # The automatic-maintenance window the box reports: { reboot_time, auto_reboot }.
    @maintenance = (result.dig(:data, "data", "maintenance") if @ok) || {}
    # What this box was prepared as: "host" (runs apps) or "balancer" (fronts others).
    # Blank when the box has never been prepared, or when we can't reach it — which
    # reads as unknown, never as a claim that it can do nothing.
    @role = ((result.dig(:data, "data", "role") if @ok) || "").to_s
    # What the box says it fronts for *other* boxes — read off the routing fragment
    # `vilice route` wrote. This is the reality half of the balancer's plan-vs-reality
    # loop; the plan is Machine#routing_table.
    @routes = (result.dig(:data, "data", "routes") if @ok) || []
    # When each target last backed up, as the box's own `backup` noted it:
    # { configured, targets: { name => { last_ok, last_failed, error } } }. Absent when
    # the box's vilice predates the fact — unknown, so no card, rather than "never".
    @backups = (result.dig(:data, "data", "backups") if @ok)
    # The certificate each served hostname hands out: [{ host, not_after, issuer,
    # valid, error }]. Absent when the box serves no hostname (or predates the check).
    @certs = (result.dig(:data, "data", "certs") if @ok) || []
  end

  # ── Backups ────────────────────────────────────────────────────────────────
  def backups_known? = @backups.is_a?(Hash)
  def backup_configured? = backups_known? && @backups["configured"] == true

  # One row per thing that should be backed up: each app the box runs, then the record
  # itself. A target with no history reads as never backed up — which, on a box with
  # a repo configured, is exactly the thing to notice.
  BackupRow = Data.define(:target, :last_ok, :last_failed, :error) do
    def record? = target == "machine"
    def never? = last_ok.nil? && last_failed.nil?
    # The most recent attempt failed: a failure newer than the last success.
    def failing? = last_failed.present? && (last_ok.nil? || last_failed > last_ok)
  end
  def backup_rows
    return [] unless backups_known?
    targets = @backups["targets"] || {}
    names = @apps.map { |a| a["name"] } + [ "machine" ]
    names.uniq.map do |name|
      run = targets[name] || {}
      BackupRow.new(target: name, last_ok: time_or_nil(run["last_ok"]),
                    last_failed: time_or_nil(run["last_failed"]), error: run["error"])
    end
  end

  # ── Certificates ───────────────────────────────────────────────────────────
  CERT_WARN_DAYS = 14
  Cert = Data.define(:host, :not_after, :issuer, :valid, :error) do
    def days_left = not_after && ((not_after - Time.current) / 1.day).floor
    # bad: not served, or does not verify; warn: valid but close to expiry.
    def level
      return :bad unless valid
      days_left && days_left < CERT_WARN_DAYS ? :warn : :ok
    end
  end
  def certs
    @certs.map do |c|
      Cert.new(host: c["host"], not_after: time_or_nil(c["not_after"]), issuer: c["issuer"],
               valid: c["valid"] == true, error: c["error"])
    end
  end

  def online? = @ok
  def machine_id = @machine["machine_id"]
  def hostname = @machine["hostname"]
  def load1 = @machine["load1"]
  def uptime_sec = @machine["uptime_sec"].to_i
  def app_count = @apps.size

  # The apps the box itself reports running — not the apps we think it has.
  # The machine view renders these: it shows what is there, not what was intended.
  def apps = @apps

  # What the box was prepared as. The machine view shapes itself around this — a
  # balancer has no container runtime, so it shows no Apps section at all. An
  # unreachable or unprepared box reports "", which reads as unknown rather than as
  # a claim that it can do nothing.
  def role = @role
  def host? = @role == "host"
  def balancer? = @role == "balancer"

  # The site addresses this box reports fronting. Same rule as `apps`: what the box
  # says, never what we asked for. An unreachable box reports nothing, which the UI
  # must read as *unknown* rather than *fronting nothing*.
  def routes = @routes

  def mem_total_bytes = @machine["mem_total_kb"].to_i * 1024
  def mem_available_bytes = @machine["mem_available_kb"].to_i * 1024

  def mem_percent
    return nil if mem_total_bytes.zero?
    (100.0 * (mem_total_bytes - mem_available_bytes) / mem_total_bytes).round
  end

  def disk_total_bytes = @machine["disk_total_bytes"].to_i
  def disk_free_bytes = @machine["disk_free_bytes"].to_i

  def disk_percent
    return nil if disk_total_bytes.zero?
    (100.0 * (disk_total_bytes - disk_free_bytes) / disk_total_bytes).round
  end

  # :ok | :warn | :crit | :offline — the worst of what we can see.
  def health
    return :offline unless online?
    [ :ok, level_for(mem_percent, MEM), level_for(disk_percent, DISK) ]
      .max_by { |l| LEVELS[l] }
  end

  def dot
    { ok: "green", warn: "yellow", crit: "red", offline: "red" }.fetch(health, "gray")
  end

  # Is this the box Vilice Console itself is running on? True only when the live
  # read carries the same machine-id Vilice Console knows itself by — "Vilice Console
  # runs anywhere", so the self case is a recognition, never a special path.
  def here?(self_id)
    self_id.present? && machine_id.present? && machine_id == self_id
  end

  # ── Hardening (read of the published fact, never a live check) ──────────────
  # Did the box ever publish a hardening posture? Absent on a box that was prepared
  # but never `harden --check`ed.
  def hardening_known? = @hardening.present?

  # The properties that are NOT in place, in plain language. Empty when fully hardened.
  def hardening_drift
    return [] unless hardening_known?
    HARDENING.filter_map { |key, line| line unless @hardening[key] }
  end

  def hardened? = hardening_known? && hardening_drift.empty?

  # When the box last published the fact (RFC3339 string), or nil.
  def hardening_checked_at = @hardening && @hardening["checked_at"]

  # green = hardened, yellow = drift, gray = never checked.
  def hardening_dot
    return "gray" unless hardening_known?
    hardened? ? "green" : "yellow"
  end

  # ── Maintenance window + pending updates (read of what the box reports) ──────
  # The box's automatic-maintenance schedule — when security patches and any reboot land.
  def maintenance_known? = @maintenance["reboot_time"].present?
  def maintenance_time = @maintenance["reboot_time"]
  def auto_reboot? = !!@maintenance["auto_reboot"]

  def update_count = @updates["count"].to_i
  def security_count = @updates["security"].to_i
  def update_packages = @updates["packages"] || []

  # Does the box report updates we could apply now? Only true when we actually know of
  # some — so "apply now" appears only when there's something to do.
  def updates_available?
    online? && (update_count.positive? || security_count.positive? || update_packages.any?)
  end

  # The plain-language health line — the old app's gem, from the live read.
  def narrative
    return "Unreachable" unless online?
    problem || "Online"
  end

  private

  def time_or_nil(value) = value.present? ? (Time.zone.parse(value.to_s) rescue nil) : nil

  def problem
    return "disk #{disk_percent}% — critically low"       if over?(disk_percent, DISK[:crit])
    return "RAM #{mem_percent}% — under severe pressure"  if over?(mem_percent, MEM[:crit])
    return "disk #{disk_percent}% — running low"          if over?(disk_percent, DISK[:warn])
    return "RAM #{mem_percent}% — under pressure"         if over?(mem_percent, MEM[:warn])
    nil
  end

  def level_for(pct, thresholds)
    return :ok if pct.nil?
    return :crit if pct >= thresholds[:crit]
    return :warn if pct >= thresholds[:warn]
    :ok
  end

  def over?(pct, threshold) = pct && pct >= threshold
end
