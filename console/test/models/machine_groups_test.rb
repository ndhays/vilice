require "test_helper"

# Grouping is the Machines page's primitive. The rule that matters most here is the
# layering one: every grouping reads layer-1 state except `owner`, which is a
# Project and is therefore an offered choice rather than a built-in column
# (decisions/console-layers.md).
class MachineGroupsTest < ActiveSupport::TestCase
  def box(name, **attrs) = Machine.create!(name: name, ssh_host: "x", **attrs)

  # There is no ungrouped view: a flat fleet list answers no question the grouped
  # one doesn't, so "Nothing" was dropped rather than kept as a default.
  test "every grouping heads its groups — there is no ungrouped view" do
    assert_not_includes MachineGroups::ALL.map(&:key), "none"
    MachineGroups::ALL.each do |grouping|
      headings = MachineGroups.apply([ box("hd-#{grouping.key}") ], grouping.key).map(&:first)
      assert headings.all?(&:present?), "#{grouping.key} produced an unheaded group"
    end
  end

  # A stale link degrades to the useful view, not to a flat one.
  test "an unknown key falls back to the default grouping rather than raising" do
    assert_equal MachineGroups::DEFAULT, MachineGroups.for("nonsense")
    assert_equal "status", MachineGroups::DEFAULT.key
    assert_equal "Not yet seen", MachineGroups.apply([ box("c-1") ], "nonsense").first.first
  end

  # Exceptions lead: the page still opens on what needs a look.
  test "reachability puts unreachable first and never-seen last" do
    up   = box("up-2",   status: "reachable")
    down = box("down-2", status: "unreachable")
    new  = box("new-2") # unknown by default

    headings = MachineGroups.apply([ up, new, down ], "status").map(&:first)
    assert_equal [ "Unreachable", "Reachable", "Not yet seen" ], headings
  end

  test "project groups by the owning client, with the homeless boxes first" do
    acme = Project.create!(name: "Acme-mg")
    owned = box("owned-3", owner: acme)
    free  = box("free-3")

    groups = MachineGroups.apply([ owned, free ], "project")
    assert_equal [ "No project", "Acme-mg" ], groups.map(&:first)
    assert_equal [ free ],  groups.first.last
    assert_equal [ owned ], groups.last.last
  end

  # The test the floor has to pass. Each grouping declares which ring it reads, so a
  # new one that reaches past the machine view has to say so out loud — dropping a
  # ring then removes exactly its own menu items and touches nothing else.
  test "every grouping declares its ring, and only these reach past the floor" do
    by_ring = MachineGroups::ALL.group_by(&:ring).transform_values { |g| g.map(&:key).sort }

    assert_equal %w[ balancer scope status ], by_ring[1], "layer-1 groupings"
    assert_equal %w[ fleet ],                 by_ring[2], "fleet runs through Install"
    assert_equal %w[ project ],               by_ring[3], "a machine's owner is a Project"
    assert_equal 1, MachineGroups.label_grouping("env").ring, "a label is the box's own"
  end

  # A fleet is a balancer and the hosts it fronts — and the balancer heads it.
  test "fleet groups a balancer with the hosts its installs land on" do
    project = Project.create!(name: "Fleet-mg")
    edge    = box("edge-mg", balancer: true, scope: "operate")
    host    = box("host-mg")
    loose   = box("loose-mg")

    install = project.installs.create!(name: "app-mg", image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                       exposure: "balanced", balancer: edge)
    install.install_targets.create!(machine: host, status: "running")

    # Passed in reverse, so the ordering below is the grouping's doing, not the input's.
    groups = MachineGroups.apply([ loose, host, edge ], "fleet")
    assert_equal [ "edge-mg", "No balancer" ], groups.map(&:first)
    assert_equal [ loose ], groups.last.last

    # The balancer heads its own fleet — the list reads the way traffic flows, and
    # the tree drawn in the view is decoration over this order rather than its cause.
    assert_equal [ edge, host ], groups.first.last
  end

  test "a label key becomes a grouping, and boxes without it group together" do
    tagged = box("tagged-4")
    tagged.labels.create!(key: "env", value: "prod")
    bare = box("bare-4")

    groups = MachineGroups.apply([ tagged, bare ], "label:env")
    assert_equal [ "prod", "no env" ], groups.map(&:first)
    assert_equal [ bare ], groups.last.last
  end

  test "only label keys actually in use on machines are offered" do
    box("labelled-5").labels.create!(key: "tier", value: "edge")
    Project.create!(name: "Proj-mg").labels.create!(key: "billing", value: "net30")

    assert_includes MachineGroups.label_keys, "tier"
    assert_not_includes MachineGroups.label_keys, "billing",
      "a label key from another model would offer a grouping that yields nothing"
  end
end
