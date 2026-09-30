require "test_helper"

# The Apps list is grouped, not filtered: a grouping shows every answer at once
# with its count, where a filter shows one at a time.
class AppGroupsTest < ActiveSupport::TestCase
  setup do
    @acme  = Project.create!(name: "Acme")
    @edge  = Machine.create!(name: "edge-1", ssh_host: "x", scope: "operate", balancer: true)
    @box   = Machine.create!(name: "box-1", ssh_host: "x")
    @down  = Machine.create!(name: "box-down", ssh_host: "x", status: "unreachable")
    @nginx = AppTemplate.create!(name: "nginx")
  end

  def app(name, project: @acme, app_template: nil, machine: @box, status: "running", **attrs)
    i = (project ? project.apps : App).create!(
      name: name, image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", app_template: app_template, **attrs)
    i.placements.create!(machine: machine, status: status) if machine
    i
  end

  test "groups by state, exceptions first and not-placed last" do
    app("failing", machine: @box, status: "failed")
    app("ok-one",  machine: @box, status: "running")
    app("nowhere", machine: nil)

    headings = AppGroups.apply(App.all.to_a, "state").map(&:first)
    assert_equal [ "Failed", "Running", "Not placed" ], headings
  end

  test "an unreachable box makes its app an exception, and it leads" do
    app("on-a-dead-box", machine: @down, status: "running")
    app("fine",          machine: @box,  status: "running")

    groups = AppGroups.apply(App.all.to_a, "state")
    assert_equal "Machine unreachable", groups.first.first
    assert_equal [ "on-a-dead-box" ], groups.first.last.map(&:name)
  end

  test "groups by app, and a custom image says so rather than hiding" do
    app("from-library", app_template: @nginx)
    app("hand-rolled")

    groups = AppGroups.apply(App.all.to_a, "app").to_h { |h, g| [ h, g.map(&:name) ] }
    assert_equal({ "nginx" => [ "from-library" ], "Custom image" => [ "hand-rolled" ] }, groups)
  end

  # Named to match the fleet list: "Fleet" groups by *which* balancer on both pages.
  test "groups by the fleet it belongs to, reading the app's own column" do
    app("behind-edge", exposure: "balanced", balancer: @edge)
    app("on-its-own")

    groups = AppGroups.apply(App.all.to_a, "fleet").to_h { |h, g| [ h, g.map(&:name) ] }
    assert_equal({ "edge-1" => [ "behind-edge" ], "No balancer" => [ "on-its-own" ] }, groups)
  end

  # Tenancy is the optional ring: a placement with no client is a legitimate state,
  # so it is a group of its own and listed first — never hidden.
  test "groups by project, with no-project as its own group first" do
    app("tenanted")
    app("untenanted", project: nil)

    headings = AppGroups.apply(App.all.to_a, "project").map(&:first)
    assert_equal [ "No project", "Acme" ], headings
  end

  test "groups by exposure" do
    app("balanced-one", exposure: "balanced", balancer: @edge)
    app("edge-one")

    headings = AppGroups.apply(App.all.to_a, "exposure").map(&:first)
    assert_equal [ "Balanced", "Edge" ], headings
  end

  # "Fleet" must mean the same thing on both list pages: group by which balancer.
  # "Edge" is taken — on the fleet list it splits balancers from hosts.
  test "the fleet axis is named the same as the fleet list's" do
    assert AppGroups::ALL.any? { |g| g.key == "fleet" && g.label == "Fleet" }
    assert MachineGroups::ALL.any? { |g| g.key == "fleet" && g.label == "Fleet" }
    assert_nil AppGroups::ALL.find { |g| g.label == "Edge" }
  end

  # A stale link degrades to the useful default view, never to a flat list or a 500.
  test "an unknown grouping falls back to the default" do
    assert_equal AppGroups::DEFAULT, AppGroups.for("no-such-axis")
    assert_equal "state", AppGroups::DEFAULT.key
  end

  # The App page's badge used to compute its own, shallower ladder — so a drifted
  # app, or one whose box had gone unreachable, read there as plainly "running".
  test "the App page's badge reads the same ladder as the list" do
    i = app("drifted", machine: @down, status: "running")
    assert_equal "unreachable", i.state
    helper = Class.new { include ApplicationHelper; include ActionView::Helpers::TagHelper }.new
    badge = helper.app_state_badge(i)
    assert_includes badge, "state-unreachable"
    assert_includes badge, "machine unreachable"
  end

  # The list's state ladder and the Status page's exception list must stay one
  # judgement — they are the same question asked on two screens.
  test "every state the model can report has a group" do
    App::STATES.each do |state|
      assert AppGroups::STATE_GROUPS.key?(state), "#{state.inspect} has no group heading"
    end
    App::EXCEPTION_STATES.each do |state|
      assert App::STATES.include?(state), "#{state.inspect} is not a state the model reports"
    end
  end
end
