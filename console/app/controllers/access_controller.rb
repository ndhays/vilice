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
    @machines = Machine.order(:name)
    @refresh  = params[:refresh].present?

    # One read per box, through the 30s observe cache. A box we cannot reach reports
    # itself as unreachable rather than vanishing from the page — a ledger you cannot
    # currently read is not the same as an empty one, and the difference matters here
    # more than anywhere.
    @ledgers = @machines.to_h do |machine|
      [ machine, Ledger.new(machine, Steward::Observe.actors(machine, refresh: @refresh)) ]
    end

    @unpinned_total = @ledgers.values.sum(&:unpinned_count)
  end

  # Ledger is a small read-model over one `actors --json` reply. It exists so the view
  # has no logic in it and so an unreachable box has a shape rather than a nil.
  class Ledger
    attr_reader :machine, :result

    def initialize(machine, result)
      @machine = machine
      @result  = result || {}
    end

    def reachable? = result[:ok].present?

    def error = result[:error].presence || "could not read the ledger"

    def actors
      return [] unless reachable?
      Array(result.dig(:data, "data", "actors"))
    end

    def granted  = actors.select { |a| a["pinned"] }
    def unpinned = actors.reject { |a| a["pinned"] }
    def unpinned_count = unpinned.size

    # Where the ledger lives on the box, so an operator can go look for themselves.
    def path = result.dig(:data, "data", "path")
  end
end
