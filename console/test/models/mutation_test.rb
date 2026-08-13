require "test_helper"

# The act registry + the compose binding the deploy ceremony needs.
class MutationTest < ActiveSupport::TestCase
  setup do
    @machine = Machine.create!(name: "op", ssh_host: "10.0.0.9", scope: "operate")
    @project = Project.create!(name: "Acme")
    @install = @project.installs.create!(name: "web", image: "ghcr.io/acme/web@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf",
                                         hostname: "acme.example", port: 8080, health: "/up")
    InstallTarget.create!(install: @install, machine: @machine, status: "running")
  end

  def build(verb, **params)
    Mutation.build(verb, machine: @machine, actor: "alice", install_id: @install.id, params: params)
  end

  test "an unknown verb is refused" do
    assert_nil Mutation.build("rm-rf", machine: @machine, actor: "alice")
  end

  test "lifecycle acts are ready immediately and target the install" do
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

  test "deploy builds the command and the stdin envelope from the Install + chosen digest" do
    digest = "sha256:abcdef1234567890"
    m = build("deploy", image: "ghcr.io/acme/web@#{digest}")
    assert_equal "deploy web --json", m.command

    env = JSON.parse(m.stdin)
    assert_equal "ghcr.io/acme/web@#{digest}", env.dig("app", "image")
    assert_equal [ "acme.example" ], env.dig("app", "hostnames")  # prefilled from the Install
    assert_equal 8080, env.dig("app", "port")
    assert_equal "/up", env.dig("app", "health")
    assert_equal "abcdef123456", m.short_digest          # the sha, trimmed to 12
    assert_match "@abcdef123456", m.summary              # which drives the record line
  end

  test "compose fields override the Install defaults" do
    m = build("deploy", image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", hostname: "staging.example", port: "9090")
    env = JSON.parse(m.stdin)
    assert_equal [ "staging.example" ], env.dig("app", "hostnames")
    assert_equal 9090, env.dig("app", "port") # coerced to an integer for Steward's appSpec
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
