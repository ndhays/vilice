require "test_helper"

# The Installs list is grouped, not filtered: a grouping shows every answer at once
# with its count, where a filter shows one at a time.
class InstallGroupsTest < ActiveSupport::TestCase
  setup do
    @acme  = Project.create!(name: "Acme")
    @edge  = Machine.create!(name: "edge-1", ssh_host: "x", scope: "operate", balancer: true)
    @box   = Machine.create!(name: "box-1", ssh_host: "x")
    @down  = Machine.create!(name: "box-down", ssh_host: "x", status: "unreachable")
    @nginx = AppTemplate.create!(name: "nginx")
  end

  def install(name, project: @acme, app_template: nil, machine: @box, status: "running", **attrs)
    i = (project ? project.installs : Install).create!(
      name: name, image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", app_template: app_template, **attrs)
    i.install_targets.create!(machine: machine, status: status) if machine
    i
  end

  test "groups by state, exceptions first and not-placed last" do
    install("failing", machine: @box, status: "failed")
    install("ok-one",  machine: @box, status: "running")
    install("nowhere", machine: nil)

    headings = InstallGroups.apply(Install.all.to_a, "state").map(&:first)
    assert_equal [ "Failed", "Running", "Not placed" ], headings
  end

  test "an unreachable box makes its install an exception, and it leads" do
    install("on-a-dead-box", machine: @down, status: "running")
    install("fine",          machine: @box,  status: "running")

    groups = InstallGroups.apply(Install.all.to_a, "state")
    assert_equal "Machine unreachable", groups.first.first
    assert_equal [ "on-a-dead-box" ], groups.first.last.map(&:name)
  end

  test "groups by app, and a custom image says so rather than hiding" do
    install("from-library", app_template: @nginx)
    install("hand-rolled")

    groups = InstallGroups.apply(Install.all.to_a, "app").to_h { |h, g| [ h, g.map(&:name) ] }
    assert_equal({ "nginx" => [ "from-library" ], "Custom image" => [ "hand-rolled" ] }, groups)
  end

  # Named to match the fleet list: "Fleet" groups by *which* balancer on both pages.
  test "groups by the fleet it belongs to, reading the install's own column" do
    install("behind-edge", exposure: "balanced", balancer: @edge)
    install("on-its-own")

    groups = InstallGroups.apply(Install.all.to_a, "fleet").to_h { |h, g| [ h, g.map(&:name) ] }
    assert_equal({ "edge-1" => [ "behind-edge" ], "No balancer" => [ "on-its-own" ] }, groups)
  end

  # Tenancy is the optional ring: a placement with no client is a legitimate state,
  # so it is a group of its own and listed first — never hidden.
  test "groups by project, with no-project as its own group first" do
    install("tenanted")
    install("untenanted", project: nil)

    headings = InstallGroups.apply(Install.all.to_a, "project").map(&:first)
    assert_equal [ "No project", "Acme" ], headings
  end

  test "groups by exposure" do
    install("balanced-one", exposure: "balanced", balancer: @edge)
    install("edge-one")

    headings = InstallGroups.apply(Install.all.to_a, "exposure").map(&:first)
    assert_equal [ "Balanced", "Edge" ], headings
  end

  # "Fleet" must mean the same thing on both list pages: group by which balancer.
  # "Edge" is taken — on the fleet list it splits balancers from hosts.
  test "the fleet axis is named the same as the fleet list's" do
    assert InstallGroups::ALL.any? { |g| g.key == "fleet" && g.label == "Fleet" }
    assert MachineGroups::ALL.any? { |g| g.key == "fleet" && g.label == "Fleet" }
    assert_nil InstallGroups::ALL.find { |g| g.label == "Edge" }
  end

  # A stale link degrades to the useful default view, never to a flat list or a 500.
  test "an unknown grouping falls back to the default" do
    assert_equal InstallGroups::DEFAULT, InstallGroups.for("no-such-axis")
    assert_equal "state", InstallGroups::DEFAULT.key
  end

  # The Install page's badge used to compute its own, shallower ladder — so a drifted
  # install, or one whose box had gone unreachable, read there as plainly "running".
  test "the Install page's badge reads the same ladder as the list" do
    i = install("drifted", machine: @down, status: "running")
    assert_equal "unreachable", i.state
    helper = Class.new { include ApplicationHelper; include ActionView::Helpers::TagHelper }.new
    badge = helper.install_state_badge(i)
    assert_includes badge, "state-unreachable"
    assert_includes badge, "machine unreachable"
  end

  # The list's state ladder and the Status page's exception list must stay one
  # judgement — they are the same question asked on two screens.
  test "every state the model can report has a group" do
    Install::STATES.each do |state|
      assert InstallGroups::STATE_GROUPS.key?(state), "#{state.inspect} has no group heading"
    end
    Install::EXCEPTION_STATES.each do |state|
      assert Install::STATES.include?(state), "#{state.inspect} is not a state the model reports"
    end
  end
end
