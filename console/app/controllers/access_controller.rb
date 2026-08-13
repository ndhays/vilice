# The Access destination — the rights ledger, fleet-wide. Who may act on which box,
# at what scope, and with which key.
#
# It is read straight off each box through `steward actors`, not from anything we
# store: authorized_keys *is* the ledger, and a copy of it in our database would be a
# second answer to "who can act here" that could quietly disagree with the box. So
# this page has no model behind it and nothing to keep in sync — it asks.
#
# Observe only. It holds an observe-scoped key, changes nothing, and writes no Event.
# Granting and revoking happen on the box (or on a machine page), never here.
class AccessController < ApplicationController
  def index
    @q     = params[:q].to_s.strip
    @group = params[:group].presence || AccessGroups::DEFAULT.key

    # One read per box, through the 30s observe cache.
    reads = Machine.order(:name).to_h { |m| [ m, Steward::Observe.actors(m) ] }

    # A box we cannot reach keeps a place on the page rather than vanishing from it.
    # A ledger you cannot currently read is not the same as an empty one, and the
    # difference matters here more than anywhere: the dangerous misreading is "no
    # lines shown" meaning "nobody has access". So the unreadable boxes are their own
    # panel, never rows — they have no lines to show, and inventing a row for them
    # would be inventing an answer.
    @unreadable = reads.reject { |_, r| r.is_a?(Hash) && r[:ok] }
                       .map { |m, r| [ m, r.try(:[], :error).presence || "could not read the ledger" ] }

    readable = reads.select { |_, r| r.is_a?(Hash) && r[:ok] }
    lines = readable.flat_map do |machine, result|
      Array(result.dig(:data, "data", "actors")).map { |a| AccessLine.from(machine, a) }
    end

    # Counted before the search, because the headline is the state of the fleet, not
    # the state of the query.
    @total       = lines.size
    @boxes_read  = readable.size
    @ungated     = lines.count(&:ungated?)
    # Where the ledger lives, so an operator can go look for themselves. Collected
    # rather than assumed: it is derived from the steward user's home on each box.
    @paths       = readable.values.filter_map { |r| r.dig(:data, "data", "path") }.uniq

    lines   = lines.select { |l| l.matches?(@q) }
    @lines  = lines
    @groups = AccessGroups.apply(lines, @group)
  end

  # Re-read every box's ledger, bypassing the 30s cache. A POST, not a GET, for the
  # same reason machines#refresh is: it opens an SSH connection to every box in the
  # fleet, and a GET must be safe to repeat unasked.
  def refresh
    Machine.find_each { |m| Steward::Observe.actors(m, refresh: true) }
    redirect_to access_path(q: params[:q].presence, group: params[:group].presence)
  end
end
