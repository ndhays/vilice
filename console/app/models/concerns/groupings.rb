# Shared grouping mechanism for the list pages. Lifted out of MachineGroups when the
# Installs list wanted the same thing, the way Searchable was lifted out of AppTemplate.search
# (decisions/open/list-search.md) — the *mechanism* is shared; each page keeps its own
# `ALL` and `DEFAULT`, because what a fleet groups by and what a set of placements
# groups by are different questions.
#
# Grouping, not filtering, is the primitive these pages want. A list answers "what is
# the shape of this?" — how many are failing, which have no home — and a filter shows
# one answer at a time where a grouping shows all of them at once, with the counts, in
# one look.
module Groupings
  # `of` maps a record to [order, label]: `order` fixes the sequence of the groups
  # (exceptions first, so a page still leads with what needs a look), `label` is the
  # heading.
  #
  # `ring` says which of the three rings a grouping reads
  # (decisions/console-layers.md) — 1 machine view, 2 placement, 3 tenancy. It is the
  # honest version of a flag: a grouping above its page's own ring is one the page
  # could not offer if that ring were never mounted, and naming *which* ring says how
  # far it reaches rather than just that it does.
  #
  # `within` optionally orders the records *inside* a group; without it they keep the
  # order they arrived in (by name).
  Grouping = Data.define(:key, :label, :ring, :of, :within)

  # Resolve a `group=` param. An unknown key lands on the default, so a stale link
  # degrades to the useful view rather than to a flat list.
  def for(key)
    self::ALL.find { |g| g.key == key.to_s } || self::DEFAULT
  end

  # [[heading, records], …]. The list is always grouped — there is no ungrouped view,
  # because a flat list answers no question the grouped one doesn't.
  def apply(records, key)
    grouping = self.for(key)

    records.group_by { |r| grouping.of.call(r) }
           .sort_by { |(order, heading), _| [ order, heading.to_s.downcase ] }
           .map { |(_, heading), group|
             [ heading, grouping.within ? group.sort_by(&grouping.within) : group ]
           }
  end
end
