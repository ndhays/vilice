# One line of the displayed chain — the merge of the two records
# (decisions/two-records.md), in a single shape the timeline can render:
#
#   - from a Steward Console Event   → an act Steward Console authored (a human behind it),
#   - from a Steward record entry → a box act; authored if Steward Console's own client
#     issued it, otherwise only witnessed (a direct CLI, the timer, another plane).
#
# A presentation value, not persisted.
ChainItem = Struct.new(:at, :actor, :action, :summary, :origin, :machine, :project,
                       :outcome, :detail, keyword_init: true) do
  def self.from_event(event)
    new(
      at: event.at, actor: event.actor, action: event.action,
      summary: event.summary.presence || event.action,
      origin: :authored, machine: event.machine, project: event.project,
      outcome: event.outcome, detail: event.detail
    )
  end

  # `client` is the name Steward Console's own scoped key records under; an entry under
  # that name is one Steward Console issued (authored), anything else is witnessed.
  def self.from_record_entry(entry, client:)
    new(
      at: (Time.zone.parse(entry["time"].to_s) rescue nil) || Time.current,
      actor: entry["actor"], action: entry["action"],
      summary: [ entry["action"], *entry["args"] ].compact.join(" "),
      origin: entry["actor"] == client ? :authored : :witnessed
    )
  end

  def witnessed? = origin == :witnessed
end
