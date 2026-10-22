require "test_helper"

# The act registry + the compose binding the deploy ceremony needs.
class MutationTest < ActiveSupport::TestCase
  setup do
    @machine = Machine.create!(name: "op", ssh_host: "10.0.0.9", scope: "operate")
    @project = Project.create!(name: "Acme")
    @app = @project.apps.create!(name: "web", image: "ghcr.io/acme/web@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf",
                                         hostname: "acme.example", port: 8080, health: "/up")
    Placement.create!(app: @app, machine: @machine, status: "running")
  end

  def build(verb, **params)
    Mutation.build(verb, machine: @machine, actor: "alice", app_id: @app.id, params: params)
  end

  # An app the box reports that we hold no App for is acted on by name.
  test "an act binds to an app by name when we hold no App for it" do
    m = Mutation.build("restart", machine: @machine, actor: "alice", name: "stray")
    assert_equal "restart stray --json", m.command
    assert_nil m.app
    assert_equal "stray on op", m.summary
  end

  test "a name finds the App we hold, so the record entry is tied to it" do
    m = Mutation.build("stop", machine: @machine, actor: "alice", name: "web")
    assert_equal @app, m.app
  end

  test "a name that is not an app name is refused" do
    [ "", "-rf", "web --all", "a/b", "web;id" ].each do |bad|
      assert_nil Mutation.build("remove", machine: @machine, actor: "alice", name: bad), bad.inspect
    end
  end

  test "deploy needs an App — a name alone carries no spec" do
    assert_nil Mutation.build("deploy", machine: @machine, actor: "alice", name: "stray")
  end

  test "backup and restore follow the app; the record has its own" do
    assert_equal "backup web --json", build("backup").command
    assert_equal "restore web --json", build("restore").command
    record = Mutation.build("backup-record", machine: @machine, actor: "alice")
    assert_equal "backup --machine --json", record.command
    assert_equal "backup", record.act.verb
    assert_equal "the record on op", record.summary
  end

  test "registry-logout takes a registry host and nothing else" do
    m = Mutation.build("registry-logout", machine: @machine, actor: "alice", params: { registry: "ghcr.io" })
    assert_equal "registry-logout ghcr.io --json", m.command
    [ nil, "", "ghcr.io --all", "ghcr.io/acme", "-x" ].each do |bad|
      assert_nil Mutation.build("registry-logout", machine: @machine, actor: "alice", params: { registry: bad }), bad.inspect
    end
  end

  test "the acts that take something away are marked" do
    assert build("remove").danger?
    assert build("restore").danger?
    refute build("restart").danger?
  end

  test "an unknown verb is refused" do
    assert_nil Mutation.build("rm-rf", machine: @machine, actor: "alice")
  end

  test "lifecycle acts are ready immediately and target the app" do
    m = build("restart")
    refute m.needs_compose?
    assert m.composed?
    assert_equal "restart web --json", m.command
    assert_nil m.stdin
  end

  test "deploy needs a compose step and is only ready once an image is picked" do
    m = build("deploy")
    assert m.needs_compose?
    refute m.composed?, "no image yet"
    assert build("deploy", image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e").composed?
  end

  test "deploy builds the command and the stdin envelope from the App + chosen digest" do
    digest = "sha256:abcdef1234567890"
    m = build("deploy", image: "ghcr.io/acme/web@#{digest}")
    assert_equal "deploy web --json", m.command

    env = JSON.parse(m.stdin)
    assert_equal "ghcr.io/acme/web@#{digest}", env.dig("app", "image")
    assert_equal [ "acme.example" ], env.dig("app", "hostnames")  # prefilled from the App
    assert_equal 8080, env.dig("app", "port")
    assert_equal "/up", env.dig("app", "health")
    assert_equal "abcdef123456", m.short_digest          # the sha, trimmed to 12
    assert_match "@abcdef123456", m.summary              # which drives the record line
  end

  test "compose fields override the App defaults" do
    m = build("deploy", image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", hostname: "staging.example", port: "9090")
    env = JSON.parse(m.stdin)
    assert_equal [ "staging.example" ], env.dig("app", "hostnames")
    assert_equal 9090, env.dig("app", "port") # coerced to an integer for Vilice's appSpec
  end

  test "rollback is parameterless — no compose, no stdin" do
    m = build("rollback")
    refute m.needs_compose?
    assert_equal "rollback web --json", m.command
    assert_nil m.stdin
  end

  test "remove is parameterless and app-scoped" do
    m = build("remove")
    refute m.needs_compose?
    assert_equal "remove web --json", m.command
    assert_nil m.stdin
  end
end
