require "test_helper"

# One ladder, defined on the target and folded by the install. It used to be written
# twice — the install had the seven states, a target row badged its raw `status` — so
# a row could read "running" under a header that said "unreachable".
class InstallTargetStateTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Ladder")
    @up   = Machine.create!(name: "up-1", ssh_host: "x", scope: "operate", status: "reachable")
    @down = Machine.create!(name: "down-1", ssh_host: "x", scope: "operate", status: "unreachable")
    @install = @project.installs.create!(name: "app", image: "img@sha256:want")
  end

  def target(machine: @up, **attrs) = @install.install_targets.create!(machine: machine, **attrs)

  test "a target on an unreachable box is unreachable, whatever its stored status says" do
    t = target(machine: @down, status: "running")
    assert_equal "running", t.status      # what we last stored
    assert_equal "unreachable", t.state   # what it actually means
  end

  test "a running target whose image differs from the desired one has drifted" do
    t = target(status: "running", current_image: "img@sha256:old", desired_image: "img@sha256:want")
    assert_equal "drift", t.state
  end

  test "failed outranks everything" do
    assert_equal "failed", target(machine: @down, status: "failed").state
  end

  test "the install takes the worst of its targets" do
    target(status: "running", current_image: "img@sha256:want", desired_image: "img@sha256:want")
    target(machine: @down, status: "running")
    assert_equal "unreachable", @install.reload.state
  end

  test "no live target is unplaced, not running" do
    assert_equal "unplaced", @install.state
    target(status: "retired")
    assert_equal "unplaced", @install.reload.state
  end

  # Every act travels scoped SSH to that box. On one we cannot reach, all of them fail.
  test "a target is actionable only with operate and a reachable box" do
    assert target(status: "running").actionable?
    assert_not target(machine: @down, status: "running").actionable?
    observe = Machine.create!(name: "obs-1", ssh_host: "x", status: "reachable")
    assert_not target(machine: observe, status: "running").actionable?
  end
end
