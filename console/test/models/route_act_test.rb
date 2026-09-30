require "test_helper"

# Applying a balancer's table is an act like any other — allowlisted verb, table derived
# at send time, recorded before it runs (decisions/drift-is-surfaced-never-closed.md:
# nothing converges on its own).
class RouteActTest < ActiveSupport::TestCase
  setup do
    @edge    = Machine.create!(name: "edge-1", ssh_host: "10.9.9.1", scope: "operate",
                               ssh_private_key: "k", status: "reachable", balancer: true)
    @backend = Machine.create!(name: "b1", ssh_host: "10.0.0.1", scope: "operate",
                               ssh_private_key: "k", status: "reachable")
    @app = App.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca", hostname: "app.example.com",
                               exposure: "balanced", balancer: @edge)
    @app.placements.create!(machine: @backend, status: "running")
  end

  test "route is machine-scoped and needs no app" do
    m = Mutation.build("route", machine: @edge, actor: "nick@example.com")
    assert m, "route must resolve without an app"
    assert_nil m.app
    assert_equal "route --json", m.command
  end

  # The table is built when the act is sent, not stored — so it always describes the
  # placements as they are now.
  test "the table rides stdin, derived at send time" do
    m = Mutation.build("route", machine: @edge, actor: "nick@example.com")
    assert_equal '{"routes":[{"hostnames":["app.example.com"],"upstreams":["10.0.0.1:80"]}]}', m.stdin

    # Another box starts serving; the same act now sends a wider table with no edit.
    other = Machine.create!(name: "b2", ssh_host: "10.0.0.2", scope: "operate",
                            ssh_private_key: "k", status: "reachable")
    @app.placements.create!(machine: other, status: "running")
    m2 = Mutation.build("route", machine: @edge.reload, actor: "nick@example.com")
    assert_includes m2.stdin, "10.0.0.2:80"
  end

  # The record line has to say what the edge will serve. "routed edge-1" tells a later
  # reader nothing about what changed.
  test "the recorded summary names the hostnames and upstream count" do
    m = Mutation.build("route", machine: @edge, actor: "nick@example.com")
    assert_equal "edge-1 → app.example.com across 1 upstreams", m.summary
    assert_equal "routed", m.action
  end

  test "a balancer fronting nothing says so rather than looking broken" do
    @app.update!(balancer: nil)
    m = Mutation.build("route", machine: @edge.reload, actor: "nick@example.com")
    assert_equal "edge-1 — fronting nothing", m.summary
    assert_equal '{"routes":[]}', m.stdin
  end
end
