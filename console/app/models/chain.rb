# Assembles one box's timeline from the two records (decisions/two-records.md): this
# console's events, and the box's own entries. Three things happen on the way, each
# because the raw merge said something untrue or said it several times:
#
# 1. **A step joins its command.** `prepare` writes `prepare`, then `prepare-role`,
#    then `authorize-binary` — one run, three entries. The steps are folded under the
#    command they belong to (same actor, within a few seconds, in the order written),
#    rather than drawn as three things somebody did.
# 2. **One act, one line.** An act this console sent is in both records: our event
#    (the person, the outcome, the reply) and the box's entry under our key's name (the
#    seq and hash that prove the box wrote it first). They are one act, so they are one
#    line — the event, carrying the box's entry. Matched on verb and time.
# 3. **A run of repeats is one line.** A refused timer writes the same refusal every
#    minute; forty of them are one fact with a count and a span.
module Chain
  STEP_WINDOW  = 5.seconds  # a command's steps are written in the same breath
  MATCH_WINDOW = 2.minutes  # our event and the box's entry for one act

  module_function

  def for_machine(events, entries, client:, limit: 40)
    own = events.map { |e| ChainItem.from_event(e) }
    box = fold_steps(entries.map { |e| ChainItem.from_record_entry(e, client: client) }
                            .reject(&:status?))
    box = attach_to_events(own, box)
    collapse_repeats((own + box).sort_by(&:at).reverse).first(limit)
  end

  # Oldest first, so a step meets the command written just before it.
  def fold_steps(items)
    items.sort_by { |i| [ i.at, i.entry&.dig("seq").to_i ] }.each_with_object([]) do |item, out|
      parent = out.reverse.find { |p| !p.step? }
      if item.step? && parent && parent.actor == item.actor && item.at - parent.at <= STEP_WINDOW
        (parent.steps ||= []) << item
      else
        out << item
      end
    end
  end

  # Box entries our own key wrote, matched to the event that sent them. The event wins
  # the line; the box's entry rides along as proof. Unmatched ones stay — an act our key
  # did that no event records (an old console, another deployment of this one) is still
  # an act.
  def attach_to_events(own, box)
    unclaimed = own.select { |e| e.verb.present? }
    box.reject do |item|
      next false unless item.kind == :command && !item.witnessed?
      event = unclaimed.find { |e| e.verb == item.verb && (e.at - item.at).abs <= MATCH_WINDOW }
      next false unless event
      unclaimed.delete(event)
      event.box_entry = item.entry
      true
    end
  end

  # Newest first; a run of the same entry becomes its newest, counting the rest.
  def collapse_repeats(items)
    items.each_with_object([]) do |item, out|
      last = out.last
      if last&.same_as?(item) && last.entry.present?
        last.repeats = (last.repeats || 1) + 1
        last.first_at = item.at
      else
        out << item
      end
    end
  end
end
