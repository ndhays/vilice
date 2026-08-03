require "test_helper"

# An install's name/port/health are deployed verbatim, so they're validated against the
# box's rules (steward validateState/validClient) — fail here, before the act.
class InstallTest < ActiveSupport::TestCase
  setup { @project = Project.create!(name: "Acme") }

  test "name must be box-safe — [A-Za-z0-9_-], the charset Steward accepts" do
    assert Install.new(project: @project, name: "web-1").valid?
    bad = Install.new(project: @project, name: "My App")
    assert_not bad.valid?
    assert_includes bad.errors[:name], "may use letters, digits, dashes, and underscores"
    assert_not Install.new(project: @project, name: "web/edge").valid?   # no slashes — it's a filename
  end

  test "port and health mirror the box's bounds, or are blank" do
    assert Install.new(project: @project, name: "web", port: 8080, health: "/up").valid?
    assert Install.new(project: @project, name: "web", port: nil, health: nil).valid?
    assert_not Install.new(project: @project, name: "web", port: 80).valid?       # below 1024
    assert_not Install.new(project: @project, name: "web", health: "up").valid?   # no leading /
  end

  test "volumes must look like source:/container-path, or be absent" do
    assert Install.new(project: @project, name: "web", config: { "volumes" => [] }).valid?
    assert Install.new(project: @project, name: "web",
                       config: { "volumes" => ["storage:/rails/storage"] }).valid?
    assert Install.new(project: @project, name: "web",            # host path + opts
                       config: { "volumes" => ["/srv/x:/data:ro"] }).valid?
    bad = Install.new(project: @project, name: "web", config: { "volumes" => ["storage"] })
    assert_not bad.valid?   # no container path
    assert_match(/must look like/, bad.errors[:base].first)
    assert_not Install.new(project: @project, name: "web",
                           config: { "volumes" => ["storage:relative"] }).valid?   # path not absolute
  end

  test "deploy_envelope carries declared volumes as the AppConfig `volumes` key" do
    install = Install.new(project: @project, name: "web",
                          config: { "volumes" => ["storage:/rails/storage"] })
    env = install.deploy_envelope(image: "ghcr.io/acme/web@sha256:abc")
    assert_equal ["storage:/rails/storage"], env.dig(:app, :volumes)
  end

  test "deploy_envelope omits volumes when none are declared" do
    install = Install.new(project: @project, name: "web")
    env = install.deploy_envelope(image: "ghcr.io/acme/web@sha256:abc")
    assert_not env[:app].key?(:volumes)
  end

  # The inversion (decisions/console-layers.md). Placement doesn't depend on tenancy:
  # an install needs a box, not a client.
  test "a project is optional — a placement with no tenant is valid" do
    assert Install.new(name: "pihole", image: "img@sha256:abc").valid?
  end

  # Names are free fleet-wide because the namespace they land in is the box. Two
  # projects, or no project at all, may each run an `api`; `InstallTarget` is what
  # refuses two of them on one machine (see install_target_test).
  test "the same name may exist many times across the fleet" do
    @project.installs.create!(name: "api", image: "img@sha256:abc")
    assert Install.new(project: @project, name: "api").valid?   # even within one project
    assert Install.new(name: "api").valid?
  end

  # ── The intention (decisions/drift-is-surfaced-never-closed.md) ───────────────

  test "count defaults to one box and must be a positive integer" do
    assert_equal 1, Install.new.count
    assert Install.new(name: "web", count: 3).valid?
    assert_not Install.new(name: "web", count: 0).valid?
    assert_not Install.new(name: "web", count: -1).valid?
  end

  # Replication is stateless-only: a volume is data on *that box's* disk, so N replicas
  # would be N diverging datasets. Derived from the spec rather than a flag, so it can't
  # disagree with the spec.
  test "an app that declares a volume is single-placement" do
    stateful = Install.new(name: "db", count: 2, config: { "volumes" => [ "data:/var/lib" ] })
    assert_not stateful.replicable?
    assert_not stateful.valid?
    assert_match(/must be 1/, stateful.errors[:count].first)
    assert_match(/own copy of that data/, stateful.errors[:count].first)

    stateful.count = 1
    assert stateful.valid?, "a stateful app may still be placed on one box"
  end

  test "a stateless app may ask for several boxes" do
    assert Install.new(name: "web", count: 4).valid?
    assert Install.new(name: "web").replicable?
  end

  # The gap is signed, and reality comes from what the box reported — not from our
  # having asked. A target we placed but that isn't running yet doesn't count as serving.
  test "the placement gap counts boxes actually serving, not boxes asked for" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate", ssh_private_key: "k")
    install = @project.installs.create!(name: "web", image: "img@sha256:abc", count: 2)

    assert_equal 0, install.serving_count
    assert_equal(-2, install.placement_gap)      # asked 2, serving 0
    assert_not install.in_step?

    install.install_targets.create!(machine: machine, status: "pending")
    assert_equal 0, install.reload.serving_count, "pending is placed, not serving"

    install.install_targets.first.update!(status: "running")
    assert_equal 1, install.reload.serving_count
    assert_equal(-1, install.placement_gap)
  end

  # An unreachable box is not serving. The whole point of the layer is that reality is
  # read from the box, so a box we cannot reach cannot be counted as satisfying intent.
  test "a running target on an unreachable box does not count as serving" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate",
                              ssh_private_key: "k", status: "unreachable")
    install = @project.installs.create!(name: "web", image: "img@sha256:abc", count: 1)
    install.install_targets.create!(machine: machine, status: "running")

    assert_equal 0, install.serving_count
    assert_equal(-1, install.placement_gap)
  end

  test "serving more boxes than asked for is a positive gap, not an error" do
    install = @project.installs.create!(name: "web", image: "img@sha256:abc", count: 1)
    2.times do |i|
      m = Machine.create!(name: "b#{i}", ssh_host: "10.0.0.#{i}", scope: "operate",
                          ssh_private_key: "k", status: "reachable")
      install.install_targets.create!(machine: m, status: "running")
    end

    assert_equal 2, install.reload.serving_count
    assert_equal 1, install.placement_gap
    assert install.valid?, "over-placement is a gap to surface, never a validation failure"
  end

  # A retired target is gone, not a placement sitting at zero.
  test "retired targets leave the intention short rather than lingering" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate",
                              ssh_private_key: "k", status: "reachable")
    install = @project.installs.create!(name: "web", image: "img@sha256:abc", count: 1)
    target  = install.install_targets.create!(machine: machine, status: "running")
    assert install.reload.in_step?

    target.update!(status: "retired")
    assert_equal 0, install.reload.serving_count
    assert_equal(-1, install.placement_gap)
    assert_empty install.live_targets
  end
end
