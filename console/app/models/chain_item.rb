# One line of the displayed chain — the merge of the two records
# (decisions/two-records.md), in a single shape the timeline can render:
#
#   - from a Steward Console Event   → an act Steward Console authored (a human behind it),
#   - from a Steward record entry → a box act; authored if Steward Console's own client
#     issued it, otherwise only witnessed (a direct CLI, the timer, another plane).
#
# A presentation value, not persisted.
#
# Each also carries its exact form, for the entry's lower levels: the `command` that ran
# (nil for an act recorded here that sent nothing to a box), the `output` the box
# replied with, and `entry` — the record entry itself, as stored.
ChainItem = Struct.new(:at, :actor, :action, :summary, :origin, :machine, :project,
                       :outcome, :detail, :command, :output, :entry, keyword_init: true) do
  def self.from_event(event)
    new(
      at: event.at, actor: event.actor, action: event.action,
      summary: event.summary.presence || event.action,
      origin: :authored, machine: event.machine, project: event.project,
      outcome: event.outcome, detail: event.detail,
      command: event.raw&.dig("command").presence&.then { |c| "steward #{c}" },
      output: event.output,
      entry: event.attributes.except("raw", "output").merge("command" => event.raw&.dig("command")).compact
    )
  end

  # `client` is the name Steward Console's own scoped key records under; an entry under
  # that name is one Steward Console issued (authored), anything else is witnessed.
  def self.from_record_entry(entry, client:)
    new(
      at: (Time.zone.parse(entry["time"].to_s) rescue nil) || Time.current,
      actor: entry["actor"], action: entry["action"],
      summary: [ entry["action"], *entry["args"] ].compact.join(" "),
      origin: entry["actor"] == client ? :authored : :witnessed,
      # The box records the verb and the arguments it was given, so the command is read
      # straight off the entry. (Output flags such as --json are not part of the act,
      # and the box does not record them.)
      command: [ "steward", entry["action"], *entry["args"] ].compact.join(" "),
      entry: entry
    )
  end

  def witnessed? = origin == :witnessed

  # Free-text search over an assembled chain. The machine page's record is the merge
  # of two sources — our events and the box's own entries — so it cannot be filtered
  # with a relation; it is filtered here, over what an entry actually says.
  def matches?(query)
    return true if query.blank?
    [ actor, action, summary ].compact.join(" ").downcase.include?(query.downcase)
  end

  # A routine status sample, from either record — the box's own timer entries
  # arrive here the same way Steward Console's do. Judged by the same rule as
  # `Event.acts`, so one definition covers both streams.
  def status? = Event::STATUS_ACTIONS.include?(action.to_s.downcase)
end
