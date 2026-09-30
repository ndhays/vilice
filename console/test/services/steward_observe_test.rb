require "test_helper"

# Observe reads reconcile Steward Console's stored projection of a box — reachability and
# the running image — so the Status page and the drift rollup read something true
# (decisions/observe-reconciliation.md). The transport is stubbed; nothing hits SSH.
class StewardObserveTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Acme")
    @machine = Machine.create!(name: "box1", ssh_host: "10.0.0.5", ssh_private_key: "k", owner: @project)
  end

  # status data envelope in the shape Steward.read returns: { ok:, data:, at: }.
  def status_result(apps: [], at: Time.current)
    { ok: true, at: at,
      data: { "data" => { "machine" => { "hostname" => "box1.local" }, "apps" => apps } } }
  end

  test "a successful read marks the machine reachable and stamps last_seen_at" do
    at = Time.current
    stub_returning(Steward, :read, status_result(at: at)) do
      Steward::Observe.status(@machine, refresh: true)
    end
    @machine.reload
    assert @machine.seen_reachable?
    assert_in_delta at.to_f, @machine.last_seen_at.to_f, 2
  end

  test "a failed read marks the machine unreachable and leaves last_seen_at" do
    @machine.update_columns(status: "reachable", last_seen_at: 1.hour.ago)
    seen = @machine.last_seen_at
    stub_returning(Steward, :read, { ok: false, error: "boom", at: Time.current }) do
      Steward::Observe.status(@machine, refresh: true)
    end
    @machine.reload
    assert @machine.seen_unreachable?
    assert_in_delta seen.to_f, @machine.last_seen_at.to_f, 2, "a failed read must not move last_seen_at"
  end

  test "current_image is reconciled from the box's reported apps (the drift input)" do
    app = @project.apps.create!(name: "web", image: "ghcr.io/acme/web@sha256:de392edde392edde392edde392edde392edde392edde392edde392edde392edd")
    placement  = app.placements.create!(machine: @machine, status: "running",
                                              desired_image: "ghcr.io/acme/web@sha256:de392edde392edde392edde392edde392edde392edde392edde392edde392edd")
    apps = [ { "name" => "web", "image" => "ghcr.io/acme/web@sha256:f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e" } ]
    stub_returning(Steward, :read, status_result(apps: apps)) do
      Steward::Observe.status(@machine, refresh: true)
    end
    assert_equal "ghcr.io/acme/web@sha256:f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e2f48e", placement.reload.current_image
    refute placement.in_sync?, "running a different image than desired = drift"
  end

  test "the name mirrors the box's hostname on the first read (still-provisional name)" do
    # A box added through the form is named after its SSH host until we reach it.
    box = Machine.create!(name: "10.0.0.7", ssh_host: "10.0.0.7", ssh_private_key: "k", owner: @project)
    stub_returning(Steward, :read, status_result) do # reports hostname box1.local
      Steward::Observe.status(box, refresh: true)
    end
    assert_equal "box1.local", box.reload.name
  end

  test "a name already mirrored (not provisional) is left alone" do
    # @machine name "box1" != ssh_host "10.0.0.5" — already its own name.
    stub_returning(Steward, :read, status_result) do
      Steward::Observe.status(@machine, refresh: true)
    end
    assert_equal "box1", @machine.reload.name
  end

  test "won't rename onto a name another box already holds" do
    Machine.create!(name: "box1.local", ssh_host: "10.9.9.9", ssh_private_key: "k")
    box = Machine.create!(name: "10.0.0.8", ssh_host: "10.0.0.8", ssh_private_key: "k")
    stub_returning(Steward, :read, status_result) do
      Steward::Observe.status(box, refresh: true)
    end
    assert_equal "10.0.0.8", box.reload.name, "stays provisional — the collision is avoided"
  end

  test "retired placements and apps we don't track are left alone" do
    app = @project.apps.create!(name: "web")
    retired = app.placements.create!(machine: @machine, status: "retired", current_image: "old")
    apps = [ { "name" => "web", "image" => "new" }, { "name" => "ghost", "image" => "x" } ]
    stub_returning(Steward, :read, status_result(apps: apps)) do
      Steward::Observe.status(@machine, refresh: true)
    end
    assert_equal "old", retired.reload.current_image, "a retired placement isn't reconciled"
  end
end
