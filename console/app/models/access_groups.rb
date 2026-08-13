# How the Access list is grouped.
#
# The page used to be one card per box, which could answer exactly one question:
# *who can act on node-005?* The other half of the job — *where can ci-deployer act?*
# — meant reading every card on the page. Both are the same set of lines seen down a
# different axis, so both are a grouping.
#
# The mechanism is shared with the fleet and installs lists (`Groupings`); only these
# axes are this page's own.
class AccessGroups
  extend Groupings
  Grouping = Groupings::Grouping

  ALL = [
    # The default, and the reason the page exists. One ordered ladder from "no ceiling
    # at all" down to read-only, so the fleet's most far-reaching keys are the first
    # thing on the screen — see AccessLine::REACH_GROUPS.
    Grouping.new(key: "reach", label: "Reach", ring: 1, within: nil,
                 of: ->(l) { AccessLine::REACH_GROUPS.fetch(l.reach, [ 4, l.reach.presence || "Unknown scope" ]) }),

    # The per-box view: who can act on this machine. What the page showed before, now
    # one axis of several. Ungated lines lead within each box, for the same reason
    # they lead the page.
    Grouping.new(key: "box", label: "Box", ring: 1,
                 of: ->(l) { [ 0, l.machine.name ] },
                 within: ->(l) { [ l.ungated? ? 0 : 1, l.reach_order, l.name ] }),

    # The question the card layout could not answer: where does this actor reach?
    # An actor holding `operate` on twelve boxes is a fact about blast radius that no
    # per-box view surfaces.
    Grouping.new(key: "actor", label: "Actor", ring: 1,
                 of: ->(l) { l.ungated? ? [ 0, "Not written by Steward" ] : [ 1, l.name ] },
                 within: ->(l) { [ l.reach_order, l.machine.name ] })
  ].freeze

  DEFAULT = ALL.find { |g| g.key == "reach" }
end
