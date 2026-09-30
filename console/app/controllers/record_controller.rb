# The Record destination — the running record of everything Steward Console has done
# across the fleet (its own authoritative acts). A forensics view: filter by
# actor / action / project, narrow by time, and search the text of what happened.
# Each box's own (witnessed) record shows on its machine page; a merged fleet view
# is still ahead (decisions/two-records.md, decisions/open/list-search.md).
#
# Four dimensions, four controls, all ANDed: **who** (actor), **what** (action),
# **for whom** (project), **when** (since) — plus free text over the rest. The
# selector grammar (`actor=`, `target=`, …) still parses in the text box for a
# hand-written or shared link, but nothing in the UI requires knowing it any more:
# the three dimensions worth a click became dropdowns.
class RecordController < ApplicationController
  # Quick time windows, in display order. Blank = all time.
  RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

  def index
    @q      = params[:q].to_s.strip
    @since  = params[:since].presence_in(RANGES.keys)

    # Each dropdown offers only values the record actually holds. A filter that can
    # return nothing is a filter that wastes a click.
    @actions  = Event.acts.distinct.order(:action).pluck(:action)
    @actors   = Event.acts.distinct.order(:actor).pluck(:actor)
    @projects = Project.where(id: Event.acts.select(:project_id)).order(:name)

    @picked  = Array(params[:actions]).select(&:present?) & @actions
    @actor   = params[:actor].presence_in(@actors)
    @project = @projects.find_by(id: params[:project_id])

    events = Event.acts.search(@q)
    events = events.where(action: @picked)      if @picked.any?
    events = events.where(actor: @actor)        if @actor
    events = events.where(project: @project)    if @project
    events = events.since(RANGES[@since].ago)   if @since
    @chain = events.latest.includes(:machine, :project, :app).limit(200)
                   .map { |e| ChainItem.from_event(e) }
  end

  helper_method :filtered?

  # Is anything narrowing the view? Drives the Clear link and the empty-state copy.
  def filtered? = @q.present? || @since.present? || @picked.any? || @actor.present? || @project.present?
end
