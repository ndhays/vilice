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
end
