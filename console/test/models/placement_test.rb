require "test_helper"

class PlacementTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P-#{SecureRandom.hex(2)}")
    @machine = Machine.create!(name: "m-#{SecureRandom.hex(2)}", ssh_host: "10.0.0.2")
    @app = @project.apps.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
  end

  test "in_sync? only when running and images match" do
    t = @app.placements.create!(machine: @machine, desired_image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    refute t.in_sync?, "pending placement is not in sync"

    t.update!(status: "running", current_image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    assert t.in_sync?

    t.update!(current_image: "img@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf")
    refute t.in_sync?, "a drifted image is not in sync"
  end

  test "one placement per machine per app" do
    @app.placements.create!(machine: @machine)
    dup = @app.placements.build(machine: @machine)
    refute dup.valid?
  end

  # Isolation #4 — name/hostname unique per machine (the box's app namespace). The real
  # case is two Projects sharing a box: per-project uniqueness can't catch a cross-tenant
  # name clash, so the join does.
  test "another project's app with the same name on the same box is refused" do
    @app.placements.create!(machine: @machine)
    clash = other_project_app(name: "web").placements.build(machine: @machine)
    refute clash.valid?
    assert_match(/unique per machine/, clash.errors[:base].join)
  end

  test "the same name on a different box is fine" do
    @app.placements.create!(machine: @machine)
    elsewhere = Machine.create!(name: "m-#{SecureRandom.hex(2)}", ssh_host: "10.0.0.3")
    assert other_project_app(name: "web").placements.build(machine: elsewhere).valid?
  end

  test "a retired placement frees its name on the box" do
    @app.placements.create!(machine: @machine).update!(status: "retired")
    assert other_project_app(name: "web").placements.build(machine: @machine).valid?
  end

  test "a duplicate hostname on the same box is refused" do
    @app.update!(hostname: "acme.example")
    @app.placements.create!(machine: @machine)
    clash = other_project_app(name: "api", hostname: "acme.example").placements.build(machine: @machine)
    refute clash.valid?
    assert_match(/Hostname/, clash.errors[:base].join)
  end

  private

  def other_project_app(name:, hostname: nil)
    Project.create!(name: "P-#{SecureRandom.hex(2)}")
           .apps.create!(name: name, image: "img@sha256:defdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefd", hostname: hostname)
  end
end
