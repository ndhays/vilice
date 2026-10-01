require "test_helper"

# An app's name/port/health are deployed verbatim, so they're validated against the
# box's rules (vilice validateState/validClient) — fail here, before the act.
class AppTest < ActiveSupport::TestCase
  setup { @project = Project.create!(name: "Acme") }

  test "name must be box-safe — [A-Za-z0-9_-], first character alphanumeric" do
    assert App.new(project: @project, name: "web-1").valid?
    bad = App.new(project: @project, name: "My App")
    assert_not bad.valid?
    assert_includes bad.errors[:name], "must start with a letter or digit, then letters, digits, dashes, and underscores"
    assert_not App.new(project: @project, name: "web/edge").valid?   # no slashes — it's a filename
    assert_not App.new(project: @project, name: "-web").valid?       # a leading dash reads as a flag
  end

  test "port and health mirror the box's bounds, or are blank" do
    assert App.new(project: @project, name: "web", port: 8080, health: "/up").valid?
    assert App.new(project: @project, name: "web", port: nil, health: nil).valid?
    assert_not App.new(project: @project, name: "web", port: 80).valid?       # below 1024
    assert_not App.new(project: @project, name: "web", health: "up").valid?   # no leading /
  end

  test "volumes must look like source:/container-path, or be absent" do
    assert App.new(project: @project, name: "web", config: { "volumes" => [] }).valid?
    assert App.new(project: @project, name: "web",
                       config: { "volumes" => ["storage:/rails/storage"] }).valid?
    assert App.new(project: @project, name: "web",            # host path + opts
                       config: { "volumes" => ["/srv/x:/data:ro"] }).valid?
    bad = App.new(project: @project, name: "web", config: { "volumes" => ["storage"] })
    assert_not bad.valid?   # no container path
    assert_match(/must look like/, bad.errors[:base].first)
    assert_not App.new(project: @project, name: "web",
                           config: { "volumes" => ["storage:relative"] }).valid?   # path not absolute
  end

  test "deploy_envelope carries declared volumes as the AppConfig `volumes` key" do
    app = App.new(project: @project, name: "web",
                          config: { "volumes" => ["storage:/rails/storage"] })
    env = app.deploy_envelope(image: "ghcr.io/acme/web@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    assert_equal ["storage:/rails/storage"], env.dig(:app, :volumes)
  end

  test "deploy_envelope omits volumes when none are declared" do
    app = App.new(project: @project, name: "web")
    env = app.deploy_envelope(image: "ghcr.io/acme/web@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    assert_not env[:app].key?(:volumes)
  end

  # The inversion (decisions/console-layers.md). Placement doesn't depend on tenancy:
  # an app needs a box, not a client.
  test "a project is optional — a placement with no tenant is valid" do
    assert App.new(name: "pihole", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca").valid?
  end

  # Names are free fleet-wide because the namespace they land in is the box. Two
  # projects, or no project at all, may each run an `api`; `Placement` is what
  # refuses two of them on one machine (see install_target_test).
  test "the same name may exist many times across the fleet" do
    @project.apps.create!(name: "api", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    assert App.new(project: @project, name: "api").valid?   # even within one project
    assert App.new(name: "api").valid?
  end

  # ── The intention (decisions/drift-is-surfaced-never-closed.md) ───────────────

  test "count defaults to one box and must be a positive integer" do
    assert_equal 1, App.new.count
    assert App.new(name: "web", count: 3, exposure: "balanced").valid?
    assert_not App.new(name: "web", count: 0).valid?
    assert_not App.new(name: "web", count: -1).valid?
  end

  # Replication is stateless-only: a volume is data on *that box's* disk, so N replicas
  # would be N diverging datasets. Derived from the spec rather than a flag, so it can't
  # disagree with the spec.
  test "an app that declares a volume is single-placement" do
    stateful = App.new(name: "db", count: 2, config: { "volumes" => [ "data:/var/lib" ] })
    assert_not stateful.replicable?
    assert_not stateful.valid?
    assert_match(/must be 1/, stateful.errors[:count].first)
    assert_match(/own copy of that data/, stateful.errors[:count].first)

    stateful.count = 1
    assert stateful.valid?, "a stateful app may still be placed on one box"
  end

  test "a stateless app behind a balancer may ask for several boxes" do
    assert App.new(name: "web", count: 4, exposure: "balanced").valid?
    assert App.new(name: "web").replicable?
  end

  # Exposure is the other gate on count, and the reason one exists at all: on the edge
  # DNS points at a single box, so a second box cannot serve the same hostname.
  test "an app defaults to the edge, one box" do
    app = App.new(name: "web")
    assert app.exposure_edge?
    assert_equal 1, app.count
  end

  test "the edge refuses a count above one" do
    edge = App.new(name: "web", count: 2)
    assert_not edge.valid?
    assert_match(/must be 1 on the edge/, edge.errors[:count].first)
    assert_match(/behind a balancer/, edge.errors[:count].first)

    edge.exposure = "balanced"
    assert edge.valid?, "the same count is fine once DNS points at a balancer"
  end

  # Both gates are real, and the stateful one wins even behind a balancer — a balancer
  # in front of N diverging datasets is still N diverging datasets.
  test "a stateful app is single-placement even behind a balancer" do
    app = App.new(name: "db", count: 2, exposure: "balanced",
                          config: { "volumes" => [ "data:/var/lib" ] })
    assert_not app.valid?
    assert_match(/own copy of that data/, app.errors[:count].first)
  end

  # The gap is signed, and reality comes from what the box reported — not from our
  # having asked. A target we placed but that isn't running yet doesn't count as serving.
  test "the placement gap counts boxes actually serving, not boxes asked for" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate", ssh_private_key: "k")
    app = @project.apps.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca",
                                        count: 2, exposure: "balanced")

    assert_equal 0, app.serving_count
    assert_equal(-2, app.placement_gap)      # asked 2, serving 0
    assert_not app.in_step?

    app.placements.create!(machine: machine, status: "pending")
    assert_equal 0, app.reload.serving_count, "pending is placed, not serving"

    app.placements.first.update!(status: "running")
    assert_equal 1, app.reload.serving_count
    assert_equal(-1, app.placement_gap)
  end

  # An unreachable box is not serving. The whole point of the layer is that reality is
  # read from the box, so a box we cannot reach cannot be counted as satisfying intent.
  test "a running placement on an unreachable box does not count as serving" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate",
                              ssh_private_key: "k", status: "unreachable")
    app = @project.apps.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca", count: 1)
    app.placements.create!(machine: machine, status: "running")

    assert_equal 0, app.serving_count
    assert_equal(-1, app.placement_gap)
  end

  test "serving more boxes than asked for is a positive gap, not an error" do
    app = @project.apps.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca", count: 1)
    2.times do |i|
      m = Machine.create!(name: "b#{i}", ssh_host: "10.0.0.#{i}", scope: "operate",
                          ssh_private_key: "k", status: "reachable")
      app.placements.create!(machine: m, status: "running")
    end

    assert_equal 2, app.reload.serving_count
    assert_equal 1, app.placement_gap
    assert app.valid?, "over-placement is a gap to surface, never a validation failure"
  end

  # A retired target is gone, not a placement sitting at zero.
  test "retired placements leave the intention short rather than lingering" do
    machine = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate",
                              ssh_private_key: "k", status: "reachable")
    app = @project.apps.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca", count: 1)
    placement  = app.placements.create!(machine: machine, status: "running")
    assert app.reload.in_step?

    placement.update!(status: "retired")
    assert_equal 0, app.reload.serving_count
    assert_equal(-1, app.placement_gap)
    assert_empty app.live_placements
  end

  # ── Whether the gap can be closed right now ────────────────────────────────
  # "Asked for 3 · serving 2" says there is a gap; it does not say whether anything can
  # be done about it. Those are different answers with different fixes, so they are
  # different questions.
  class CandidatesTest < ActiveSupport::TestCase
    setup do
      @project = Project.create!(name: "Acme")
      # Above one box needs a balancer in front — the count gate, doing its job.
      @app = @project.apps.create!(name: "web", count: 3, exposure: "balanced",
                                           image: "img@sha256:#{'a' * 64}")
      @free    = box("free", project: @project, seen: true)
      @taken   = box("taken", project: @project, seen: true)
      @app.placements.create!(machine: @taken, status: "running")
    end

    def box(name, project: nil, scope: "operate", seen: false, status: "unknown")
      m = Machine.create!(name: name, ssh_host: "10.0.0.#{name.bytes.sum % 200}",
                          scope: scope, ssh_private_key: "k", status: status,
                          owner: project, last_seen_at: seen ? Time.current : nil)
      ProjectMachine.create!(project: project, machine: m) if project
      m
    end

    test "a candidate is operate-scoped, in the project, and not already carrying it" do
      box("observer", project: @project, scope: "observe", seen: true)
      box("elsewhere", seen: true)   # no project link — not this app's to use

      assert_equal [ @free ], @app.candidate_machines
    end

    test "with no project, any operate box in the fleet is a candidate" do
      loose   = box("loose", seen: true)
      untenanted = App.create!(name: "solo", count: 2, exposure: "balanced",
                                   image: "img@sha256:#{'b' * 64}")

      assert_includes untenanted.candidate_machines, loose
      assert_includes untenanted.candidate_machines, @free
    end

    # Placing works on any candidate — it reaches nothing. The deploy that follows does
    # not, so "ready" is a narrower word than "free".
    test "ready is narrower than candidate: only boxes we have actually heard from" do
      never = box("never", project: @project)                                # no last_seen_at
      lost  = box("lost", project: @project, seen: true, status: "unreachable")

      assert_equal [ @free, lost, never ].sort_by(&:name), @app.candidate_machines.sort_by(&:name)
      assert_equal [ @free ], @app.ready_machines
      assert @app.ready_to_place?
    end

    test "short with candidates but none reached is not ready to place" do
      @free.update!(last_seen_at: nil)

      assert @app.short?
      assert @app.candidate_machines.any?
      assert_empty @app.ready_machines
      assert_not @app.ready_to_place?
    end

    test "an app in step is never ready to place, however many boxes are free" do
      @app.update!(count: 1)
      # One target, and the box reports it running, so the intention is met.
      @app.placements.sole.update!(status: "running")

      assert_not @app.short?
      assert_not @app.ready_to_place?
    end

    # The pool exists so a list can answer for many apps without a query each. Two
    # things have to be preloaded for that to hold — the machine pool *and* the app's
    # own targets — and if either stops being honoured the N+1 comes back silently.
    test "a preloaded pool and placements answer without querying per app" do
      pool  = Machine.operate.includes(:project_machines).order(:name).to_a
      loaded = App.includes(placements: :machine).find(@app.id)

      assert_queries_count(0) { loaded.candidate_machines(pool) }
      assert_equal @app.candidate_machines.map(&:id), loaded.candidate_machines(pool).map(&:id)
    end
  end
end
