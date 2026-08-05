require "test_helper"

# The balancer's table is **derived, never stored** (decisions/one-primitive-composed.md):
# computed from the installs that select it and the boxes those installs are actually
# serving from, so it cannot drift from the placements it describes.
class RoutingTableTest < ActiveSupport::TestCase
  setup do
    @edge     = balancer_box("edge-1")
    @backend1 = operate_box("b1", "10.0.0.1")
    @backend2 = operate_box("b2", "10.0.0.2")
  end

  test "an install behind a balancer becomes one route to its serving boxes" do
    install = balanced_install("web", "app.example.com", count: 2)
    serving(install, @backend1)
    serving(install, @backend2)

    routes = RoutingTable.for(@edge)
    assert_equal 1, routes.size
    assert_equal [ "app.example.com" ], routes.first.hostnames
    assert_equal [ "10.0.0.1:80", "10.0.0.2:80" ], routes.first.upstreams
  end

  # Upstreams are the backend's own edge on plain HTTP, not the app's container port —
  # that port is published on the backend's loopback and is unreachable from here.
  test "upstreams address the backend's edge, not the container port" do
    install = balanced_install("web", "app.example.com", port: 8080)
    serving(install, @backend1)

    assert_equal [ "10.0.0.1:#{RoutingTable::BACKEND_PORT}" ], RoutingTable.for(@edge).first.upstreams
    assert_equal 80, RoutingTable::BACKEND_PORT
  end

  # The rule that keeps a placement gap from becoming a 502: a box we asked for but that
  # isn't serving is not an upstream. The gap stays visible instead.
  test "a placed but not-yet-running box is not an upstream" do
    install = balanced_install("web", "app.example.com", count: 2)
    serving(install, @backend1)
    install.install_targets.create!(machine: @backend2, status: "pending")

    assert_equal [ "10.0.0.1:80" ], RoutingTable.for(@edge).first.upstreams
  end

  test "an unreachable box is not an upstream" do
    install = balanced_install("web", "app.example.com", count: 2)
    serving(install, @backend1)
    serving(install, @backend2)
    @backend2.update!(status: "unreachable")

    assert_equal [ "10.0.0.1:80" ], RoutingTable.for(@edge).first.upstreams
  end

  # A hostname with nowhere to send traffic is worse than an absent route — the box
  # would answer and 502. Steward refuses such a table anyway; we don't build one.
  test "an install with no serving box produces no route at all" do
    balanced_install("web", "app.example.com")
    assert_empty RoutingTable.for(@edge)
  end

  test "an install with no hostname produces no route" do
    install = balanced_install("web", nil)
    serving(install, @backend1)
    assert_empty RoutingTable.for(@edge)
  end

  test "installs that select another balancer are not in this one's table" do
    other = balancer_box("edge-2")
    install = Install.create!(name: "web", image: "img@sha256:abc", hostname: "app.example.com",
                              exposure: "balanced", balancer: other)
    serving(install, @backend1)

    assert_empty RoutingTable.for(@edge)
    assert_equal 1, RoutingTable.for(other).size
  end

  # The envelope is exactly what `steward route` reads on stdin — hostnames and
  # upstreams, nothing else about our model.
  test "the envelope is the shape the box parses" do
    install = balanced_install("web", "app.example.com")
    serving(install, @backend1)

    env = RoutingTable.envelope(@edge)
    assert_equal({ routes: [ { hostnames: [ "app.example.com" ], upstreams: [ "10.0.0.1:80" ] } ] }, env)
    assert_equal '{"routes":[{"hostnames":["app.example.com"],"upstreams":["10.0.0.1:80"]}]}', env.to_json
  end

  # An empty table is meaningful: it tells the box to front nothing, which is how a
  # balancer leaves service. Steward accepts it.
  test "a balancer with nothing behind it renders an empty table, not nil" do
    assert_equal({ routes: [] }, RoutingTable.envelope(@edge))
  end

  private

  def balancer_box(name)
    Machine.create!(name: name, ssh_host: "10.9.9.#{name[-1]}", scope: "operate",
                    ssh_private_key: "k", status: "reachable", balancer: true)
  end

  def operate_box(name, host)
    Machine.create!(name: name, ssh_host: host, scope: "operate",
                    ssh_private_key: "k", status: "reachable")
  end

  def balanced_install(name, hostname, count: 1, port: nil)
    Install.create!(name: name, image: "img@sha256:abc", hostname: hostname, port: port,
                    exposure: "balanced", count: count, balancer: @edge)
  end

  def serving(install, machine)
    install.install_targets.create!(machine: machine, status: "running")
  end
end
