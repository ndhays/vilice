require "test_helper"

# Projection logic for the observe side. Fixtures use the real `status --json`
# envelope shape ({ code, data: { machine, apps } }) so the parsing is honest.
class MachineStatusTest < ActiveSupport::TestCase
  # Build a Vilice.read-style result with the given machine numbers.
  def reading(mem_total: 4_000_000, mem_avail: 2_000_000,
              disk_total: 100_000_000, disk_free: 40_000_000, load1: 0.2,
              hardening: nil, updates: nil, maintenance: nil, reboot: nil)
    inner = {
      "machine" => {
        "hostname" => "ubuntu-dev", "uptime_sec" => 81_135, "load1" => load1,
        "mem_total_kb" => mem_total, "mem_available_kb" => mem_avail,
        "disk_total_bytes" => disk_total, "disk_free_bytes" => disk_free
      },
      "apps" => []
    }
    inner["hardening"] = hardening if hardening
    inner["updates"] = updates if updates
    inner["maintenance"] = maintenance if maintenance
    inner["reboot"] = reboot if reboot
    { ok: true, at: Time.current, data: { "code" => "ok", "retryable" => false, "data" => inner } }
  end

  # A published hardening fact; pass overrides to simulate drift.
  def posture(**over)
    {
      "ssh_root_login_disabled" => true, "password_auth_disabled" => true,
      "firewall_active" => true, "fail2ban_active" => true, "unattended_upgrades" => true,
      "checked_at" => "2026-06-10T12:00:00Z"
    }.merge(over.transform_keys(&:to_s))
  end

  test "projects numbers from a healthy reading" do
    s = MachineStatus.from(reading)
    assert s.online?
    assert_equal "ubuntu-dev", s.hostname
    assert_equal 0.2, s.load1
    assert_equal 50, s.mem_percent   # half used
    assert_equal 60, s.disk_percent  # 40 of 100 free
    assert_equal :ok, s.health
    assert_equal "green", s.dot
    assert_equal "Online", s.narrative
  end

  test "warns on disk pressure with a plain sentence" do
    s = MachineStatus.from(reading(disk_total: 100, disk_free: 20)) # 80% used
    assert_equal :warn, s.health
    assert_equal "yellow", s.dot
    assert_equal "disk 80% — running low", s.narrative
  end

  test "no updates reported — none available, the act stays hidden" do
    s = MachineStatus.from(reading)
    assert_not s.updates_available?
    assert_empty s.update_packages
  end

  test "reads available updates and their package list" do
    s = MachineStatus.from(reading(updates: {
      "count" => 3, "security" => 3, "packages" => %w[libssl3 openssl libc6]
    }))
    assert s.updates_available?
    assert_equal 3, s.update_count
    assert_equal %w[libssl3 openssl libc6], s.update_packages
  end

  test "reads the maintenance window the box reports" do
    s = MachineStatus.from(reading(maintenance: { "reboot_time" => "04:00", "auto_reboot" => true }))
    assert s.maintenance_known?
    assert_equal "04:00", s.maintenance_time
    assert s.auto_reboot?
  end

  test "reads a restart the box owes itself, and whether the box will do it" do
    s = MachineStatus.from(reading(reboot: { "required" => true, "packages" => %w[linux-image libc6] }))
    assert s.reboot_required?
    assert_equal %w[linux-image libc6], s.reboot_packages
    refute s.reboots_itself?, "no window means nobody restarts it but a person"

    s = MachineStatus.from(reading(reboot: { "required" => true },
                                   maintenance: { "reboot_time" => "04:00", "auto_reboot" => true }))
    assert s.reboots_itself?
    assert_equal [], s.reboot_packages
  end

  test "a box too old to report a restart reads as unknown, not as none owed" do
    s = MachineStatus.from(reading)
    refute s.reboot_known?
    refute s.reboot_required?

    s = MachineStatus.from(reading(reboot: { "required" => false }))
    assert s.reboot_known?
    refute s.reboot_required?
  end

  test "no maintenance window reported reads as unknown" do
    s = MachineStatus.from(reading)
    assert_not s.maintenance_known?
    assert_nil s.maintenance_time
  end

  test "an offline box reports no updates and no maintenance window" do
    s = MachineStatus.from({ ok: false, error: "unreachable", at: Time.current })
    assert_not s.updates_available?
    assert_not s.maintenance_known?
  end

  test "crit on severe memory pressure, and crit wins over a milder disk warn" do
    s = MachineStatus.from(reading(mem_total: 100, mem_avail: 5,      # 95% used
                                   disk_total: 100, disk_free: 20))   # 80% used
    assert_equal :crit, s.health
    assert_equal "red", s.dot
    assert_equal "RAM 95% — under severe pressure", s.narrative
  end

  test "recognizes itself only when the live machine-id matches" do
    s = MachineStatus.from(reading)
    s.raw["data"]["machine"]["machine_id"] = "abc123"
    assert_equal "abc123", s.machine_id
    assert s.here?("abc123")
    refute s.here?("different")
    refute s.here?(nil)
    refute s.here?("")
  end

  test "a box that reports no machine-id is never 'here'" do
    s = MachineStatus.from(reading) # fixture has no machine_id
    assert_nil s.machine_id
    refute s.here?("anything")
  end

  test "a box that never published a hardening fact is 'unknown', not drifted" do
    s = MachineStatus.from(reading) # no hardening block
    refute s.hardening_known?
    refute s.hardened?
    assert_empty s.hardening_drift
    assert_equal "gray", s.hardening_dot
    assert_nil s.hardening_checked_at
  end

  test "a fully hardened box reads as hardened" do
    s = MachineStatus.from(reading(hardening: posture))
    assert s.hardening_known?
    assert s.hardened?
    assert_empty s.hardening_drift
    assert_equal "green", s.hardening_dot
    assert_equal "2026-06-10T12:00:00Z", s.hardening_checked_at
  end

  test "drift is reported in plain language, yellow dot" do
    s = MachineStatus.from(reading(hardening: posture(ssh_root_login_disabled: false,
                                                      firewall_active: false)))
    refute s.hardened?
    assert_equal [ "root SSH login enabled", "firewall inactive" ], s.hardening_drift
    assert_equal "yellow", s.hardening_dot
  end

  test "an unreachable box is offline, not a crash" do
    s = MachineStatus.from({ ok: false, error: "ssh exited 255", at: Time.current })
    refute s.online?
    assert_equal :offline, s.health
    assert_nil s.mem_percent
    assert_equal "Unreachable", s.narrative
    assert_equal "ssh exited 255", s.error
  end
end
