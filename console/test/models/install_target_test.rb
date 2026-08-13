require "test_helper"

class InstallTargetTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P-#{SecureRandom.hex(2)}")
    @machine = Machine.create!(name: "m-#{SecureRandom.hex(2)}", ssh_host: "10.0.0.2")
    @install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
  end

  test "in_sync? only when running and images match" do
    t = @install.install_targets.create!(machine: @machine, desired_image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    refute t.in_sync?, "pending target is not in sync"

    t.update!(status: "running", current_image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    assert t.in_sync?

    t.update!(current_image: "img@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf")
    refute t.in_sync?, "a drifted image is not in sync"
  end

  test "one target per machine per install" do
    @install.install_targets.create!(machine: @machine)
    dup = @install.install_targets.build(machine: @machine)
    refute dup.valid?
  end

  # Isolation #4 — name/hostname unique per machine (the box's app namespace). The real
  # case is two Projects sharing a box: per-project uniqueness can't catch a cross-tenant
  # name clash, so the join does.
  test "another project's install with the same name on the same box is refused" do
    @install.install_targets.create!(machine: @machine)
    clash = other_project_install(name: "web").install_targets.build(machine: @machine)
    refute clash.valid?
    assert_match(/unique per machine/, clash.errors[:base].join)
  end

  test "the same name on a different box is fine" do
    @install.install_targets.create!(machine: @machine)
    elsewhere = Machine.create!(name: "m-#{SecureRandom.hex(2)}", ssh_host: "10.0.0.3")
    assert other_project_install(name: "web").install_targets.build(machine: elsewhere).valid?
  end

  test "a retired target frees its name on the box" do
    @install.install_targets.create!(machine: @machine).update!(status: "retired")
    assert other_project_install(name: "web").install_targets.build(machine: @machine).valid?
  end

  test "a duplicate hostname on the same box is refused" do
    @install.update!(hostname: "acme.example")
    @install.install_targets.create!(machine: @machine)
    clash = other_project_install(name: "api", hostname: "acme.example").install_targets.build(machine: @machine)
    refute clash.valid?
    assert_match(/Hostname/, clash.errors[:base].join)
  end

  private

  def other_project_install(name:, hostname: nil)
    Project.create!(name: "P-#{SecureRandom.hex(2)}")
           .installs.create!(name: name, image: "img@sha256:defdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefd", hostname: hostname)
  end
end
