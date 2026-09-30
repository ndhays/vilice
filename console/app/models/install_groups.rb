# How the Installs list is grouped.
#
# The page is placement, fleet-wide: what should run where. So the axes are the ones
# a placement actually has — how it's doing, what it is, whose it is, how it's
# reached, and what fronts it. The mechanism is shared with the fleet list
# (`Groupings`); only these axes are this page's own.
#
# **Ring 2 is the floor here**, not ring 1: an Install *is* the placement ring
# (decisions/console-layers.md). `project` is the one axis that reaches out to
# tenancy, and — as on the fleet list — it is offered as a choice rather than baked
# into the page, so with tenancy never mounted this list loses one chip and nothing
# else.
class InstallGroups
  extend Groupings
  Grouping = Groupings::Grouping

  # Exceptions first, then the transient states, then the calm ones, then not-yet-
  # placed. Same ladder as `Install::STATES` and the same order the Status page ranks
  # its exception list by, because they are the same judgement about what needs a
  # person. `unplaced` sits last: it is a placement nobody has landed yet, not a
  # fault.
  STATE_GROUPS = {
    "failed"      => [ 0, "Failed" ],
    "unreachable" => [ 1, "Machine unreachable" ],
    "drift"       => [ 2, "Drift" ],
    "deploying"   => [ 3, "Deploying" ],
    "pending"     => [ 4, "Pending" ],
    "running"     => [ 5, "Running" ],
    "unplaced"    => [ 6, "Not placed" ]
  }.freeze

  ALL = [
    Grouping.new(key: "state", label: "State", ring: 2, within: nil,
                 of: ->(i) { STATE_GROUPS.fetch(i.state, [ 7, i.state ]) }),

    # What is running, rather than where. The lens for "every copy of nginx in the
    # fleet" — the question the App Library makes worth asking. A custom image has no
    # library entry behind it and says so, rather than being hidden in an "Other".
    Grouping.new(key: "app", label: "Template", ring: 2, within: nil,
                 of: ->(i) { i.app_template ? [ 0, i.app_template.name ] : [ 1, "Custom image" ] }),

    # How it is reached, which is what decides whether a count above one can mean
    # anything (decisions/one-primitive-composed.md).
    Grouping.new(key: "exposure", label: "Exposure", ring: 2, within: nil,
                 of: ->(i) { i.exposure_balanced? ? [ 0, "Balanced" ] : [ 1, "Edge" ] }),

    # The fleet it belongs to — one balancer and what it fronts. Named **Fleet**, not
    # "Edge", to match the fleet list: there, "Edge" splits balancers from hosts while
    # "Fleet" groups by *which* balancer, and this is the second of those. One word,
    # one meaning, across both pages.
    #
    # Unlike the fleet list's version — which has to reach through installs to find the
    # relationship — an Install names its balancer directly, so this is a plain read of
    # its own column.
    Grouping.new(key: "fleet", label: "Fleet", ring: 2, within: nil,
                 of: ->(i) { i.balancer ? [ 0, i.balancer.name ] : [ 1, "No balancer" ] }),

    # The one axis that reaches into tenancy. An install with no project is a
    # placement with no tenant — a legitimate state, listed first as its own group
    # rather than hidden.
    Grouping.new(key: "project", label: "Project", ring: 3, within: nil,
                 of: ->(i) { i.project ? [ 1, i.project.name ] : [ 0, "No project" ] })
  ].freeze

  # The page opens grouped by state, for the same reason the fleet list opens on
  # reachability: the first question anyone asks a list of placements is which of
  # them is unhappy, and it costs nothing to answer before being asked.
  DEFAULT = ALL.find { |g| g.key == "state" }
end
