# How the fleet list is grouped.
#
# Grouping, not filtering, is the primitive this page wants. The Machines list
# answers "what is the shape of my fleet" — how many boxes are unreachable, which
# ones have no home — and a filter shows you one answer at a time while a grouping
# shows you all of them at once, with the counts, in one look.
#
# **Every grouping here is layer 1 except one.** Reachability, scope, and the
# balancer role read a column the box or the operator set on the box itself;
# labels are the operator's own axis. `owner` is a `Project` — one ring out
# (decisions/console-layers.md) — so it is offered as a *choice* rather than baked
# into the row. That is the test the floor has to pass: with tenancy never
# mounted, this page loses one option from a menu and nothing else.
#
# Not here yet: **role**, which is the most natural way to group a fleet and the
# purest layer-1 fact there is (the box says what it is for). It cannot be built
# until the reported role is persisted — the list does no per-machine live read,
# and doing N SSH reads to draw a list is exactly what the page must not do. It
# arrives with ingestion (#6 in decisions/open/ui-roadmap.md).
class MachineGroups
  # The mechanism — the Grouping shape, `for`, and `apply` — is shared with the
  # Apps list. Only the axes below are this page's own.
  extend Groupings
  Grouping = Groupings::Grouping

  # Reachability leads with the boxes that need attention, then the calm ones, and
  # never-seen last — it is not a fault, just a box we have not met.
  STATUS_GROUPS = {
    "unreachable" => [ 0, "Unreachable" ],
    "reachable"   => [ 1, "Reachable" ],
    "unknown"     => [ 2, "Not yet seen" ]
  }.freeze

  ALL = [
    Grouping.new(key: "status", label: "Reachability", ring: 1, within: nil,
                 of: ->(m) { STATUS_GROUPS.fetch(m.status, [ 3, m.status ]) }),

    Grouping.new(key: "scope", label: "Scope", ring: 1, within: nil,
                 of: ->(m) { m.scope == "operate" ? [ 0, "Operate" ] : [ 1, "Observe" ] }),

    Grouping.new(key: "balancer", label: "Edge", ring: 1, within: nil,
                 of: ->(m) { m.balancer? ? [ 0, "Balancers" ] : [ 1, "Hosts" ] }),

    # A fleet is one balancer and the hosts it fronts. The relationship is *not*
    # machine-to-machine — it runs through the apps a balancer fronts — so this
    # reads the placement ring, and a box appears in the fleet its apps are served
    # through. A balancer heads its own fleet.
    Grouping.new(key: "fleet", label: "Fleet", ring: 2,
                 of: ->(m) {
                   name = m.balancer? ? m.name : m.apps.filter_map { |i| i.balancer&.name }.min
                   name ? [ 0, name ] : [ 1, "No balancer" ]
                 },
                 # The balancer heads its own fleet, then the hosts it fronts — the
                 # list reads the way the traffic flows.
                 within: ->(m) { [ m.balancer? ? 0 : 1, m.name ] }),

    # Named for what it is. A machine's owner *is* a Project, and calling the
    # grouping "Owner" made the one ring-3 concept on this page sound like a
    # property of the box rather than the client it belongs to.
    Grouping.new(key: "project", label: "Project", ring: 3, within: nil,
                 of: ->(m) { m.owner ? [ 1, m.owner.name ] : [ 0, "No project" ] })
  ].freeze

  # The page opens grouped by reachability: the first question anyone asks a fleet
  # is which of it is up, and it costs nothing to answer before being asked. Also
  # where an unknown `group=` lands, so a stale link degrades to the useful view
  # rather than to a flat list.
  DEFAULT = ALL.find { |g| g.key == "status" }

  # A label key is a grouping too — `group=label:env` — because labels are the
  # operator's own axis and the whole point of them is grouping by what *they*
  # care about, not by what the system happens to model.
  LABEL_PREFIX = "label:"

  # A label key resolves to a grouping built on the spot; everything else goes to the
  # shared resolver.
  def self.for(key)
    key = key.to_s
    return label_grouping(key.delete_prefix(LABEL_PREFIX)) if key.start_with?(LABEL_PREFIX)
    super
  end

  def self.label_grouping(label_key)
    Grouping.new(key: "#{LABEL_PREFIX}#{label_key}", label: label_key, ring: 1, within: nil,
                 of: ->(m) {
                   value = m.labels.find { |l| l.key == label_key }&.value
                   # A box that does not carry the label is its own group, listed
                   # last — "no env" is an answer, not an absence to hide.
                   value.present? ? [ 0, value ] : [ 1, "no #{label_key}" ]
                 })
  end

  # The label keys actually in use on machines, so the menu offers only groupings
  # that would produce something.
  def self.label_keys
    Label.where(labelable_type: "Machine").distinct.order(:key).pluck(:key)
  end
end
