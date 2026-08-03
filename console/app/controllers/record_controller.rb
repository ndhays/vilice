# The Record destination — the running record of everything Steward Console has done
# across the fleet (its own authoritative acts). A forensics view: filter by
# actor / action / target with the label-selector grammar, narrow by time. Each
# box's own (witnessed) record shows on its machine page; a merged fleet view is
# still ahead (decisions/two-records.md, decisions/open/list-search.md).
class RecordController < ApplicationController
  # Quick time windows, in display order. Blank = all time.
  RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

  def index
    @q       = params[:q].to_s.strip
    @since   = params[:since].presence_in(RANGES.keys)
    @actions = Event.distinct.order(:action).pluck(:action)
    @picked  = Array(params[:actions]).select(&:present?) & @actions

    events = Event.search(@q)
    events = events.where(action: @picked) if @picked.any?
    events = events.since(RANGES[@since].ago) if @since
    @chain = events.latest.includes(:machine, :project, :install).limit(200)
                   .map { |e| ChainItem.from_event(e) }
  end
end
