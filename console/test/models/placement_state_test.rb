require "test_helper"

# One ladder, defined on the target and folded by the app. It used to be written
# twice — the app had the seven states, a target row badged its raw `status` — so
# a row could read "running" under a header that said "unreachable".
class PlacementStateTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Ladder")
    @up   = Machine.create!(name: "up-1", ssh_host: "x", scope: "operate", status: "reachable")
    @down = Machine.create!(name: "down-1", ssh_host: "x", scope: "operate", status: "unreachable")
    @app = @project.apps.create!(name: "app", image: "img@sha256:7ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae4")
  end

  def target(machine: @up, **attrs) = @app.placements.create!(machine: machine, **attrs)

  test "a target on an unreachable box is unreachable, whatever its stored status says" do
    t = target(machine: @down, status: "running")
    assert_equal "running", t.status      # what we last stored
    assert_equal "unreachable", t.state   # what it actually means
  end

  test "a running target whose image differs from the desired one has drifted" do
    t = target(status: "running", current_image: "img@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf", desired_image: "img@sha256:7ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae4")
    assert_equal "drift", t.state
  end

  test "failed outranks everything" do
    assert_equal "failed", target(machine: @down, status: "failed").state
  end

  test "the app takes the worst of its targets" do
    target(status: "running", current_image: "img@sha256:7ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae4", desired_image: "img@sha256:7ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae47ae4")
    target(machine: @down, status: "running")
    assert_equal "unreachable", @app.reload.state
  end

  test "no live target is unplaced, not running" do
    assert_equal "unplaced", @app.state
    target(status: "retired")
    assert_equal "unplaced", @app.reload.state
  end

  # Every act travels scoped SSH to that box. On one we cannot reach, all of them fail.
  test "a target is actionable only with operate and a reachable box" do
    assert target(status: "running").actionable?
    assert_not target(machine: @down, status: "running").actionable?
    observe = Machine.create!(name: "obs-1", ssh_host: "x", status: "reachable")
    assert_not target(machine: observe, status: "running").actionable?
  end
end
