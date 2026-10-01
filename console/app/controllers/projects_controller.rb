class ProjectsController < ApplicationController
  # How many record entries to show on the project page before linking out to the
  # full, filterable record (mirrors Home's "Latest" head-of-chain).
  RECORD_HEAD = 6

  def index
    @q = params[:q]
    projects = (@q.present? ? Project.search(@q) : Project.all)
                 .order(:name).includes(:machines, :apps, :labels)
    # While searching, show one flat list of matches; otherwise split starred out.
    @starred, @projects = @q.present? ? [ [], projects.to_a ] : projects.partition(&:starred?)
  end

  # Add a client — a control-plane act with no box. Recorded with attribution,
  # append-only, in one transaction (mirrors machines#create).
  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)
    ActiveRecord::Base.transaction do
      @project.save!
      Event.record!(actor: Current.user.email_address, action: "added",
                    project: @project, summary: @project.name)
    end
    redirect_to @project, notice: "Added #{@project.name}."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  # Star / unstar — a control-plane act, recorded with attribution (the focus lens).
  def star
    project = Project.find(params[:id])
    ActiveRecord::Base.transaction do
      project.update!(starred: !project.starred?)
      verb = project.starred? ? "starred" : "unstarred"
      Event.record!(actor: Current.user.email_address, action: verb,
                    project: project, summary: project.name)
    end
    redirect_back fallback_location: project
  end

  def edit
    @project = Project.find(params[:id])
  end

  def update
    @project = Project.find(params[:id])
    ActiveRecord::Base.transaction do
      @project.update!(project_params)
      Event.record!(actor: Current.user.email_address, action: "edited",
                    project: @project, summary: @project.name)
    end
    redirect_to @project, notice: "Updated #{@project.name}."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  # Delete a project — guarded. Destroying it cascades to its App/Placement
  # rows, but those represent apps that may still be running on the boxes (Vilice Console
  # forgetting an app does NOT `vilice remove` it). So refuse while any live app
  # remains — the operator removes them first. The project's events nullify, so the
  # record survives the deletion. Mirrors the detach-machine guard.
  def destroy
    project = Project.find(params[:id])

    if runs_live_apps?(project)
      return redirect_to project,
        alert: "#{project.name} still has live apps — remove them first."
    end

    # A box can't be orphaned: deleting an owner is blocked until its boxes are
    # transferred or released (decisions/machine-ownership.md). Never a silent nullify.
    if (owned = project.owned_machines).any?
      return redirect_to project,
        alert: "#{project.name} still owns #{owned.map(&:name).to_sentence} — transfer or release first."
    end

    ActiveRecord::Base.transaction do
      Event.record!(actor: Current.user.email_address, action: "removed",
                    project: project, summary: project.name)
      project.destroy!
    end
    redirect_to projects_path, notice: "Removed #{project.name}."
  end

  def show
    @project  = Project.find(params[:id])
    @apps = @project.apps.includes(:app_template, :version, placements: :machine).order(:name)
    # Two clean groups: boxes this project OWNS (its hardware), and boxes it uses
    # but another project owns (shared in). machine-ownership.md.
    @owned_machines  = @project.owned_machines.includes(:labels, :owner).order(:name)
    @shared_machines = @project.machines.where.not(owner_id: @project.id)
                               .includes(:labels, :owner).order(:name)
    # Fleet machines this project could still take on: not already linked, and that
    # permit this project — it owns them, or they're shared with everyone, or it's on
    # their allowlist (decisions/machine-ownership.md). A box you don't own / aren't granted
    # never appears, so client 4 can't reach client 3's box.
    @attachable = Machine.where.not(id: @project.machine_ids).order(:name)
                         .select { |m| m.permits?(@project) }
    # Show only the head of the record here — the spine stays visible but bounded,
    # leaving room for Apps and Machines. The full, filterable record
    # is one click away, scoped to this project (mirrors Home's "Latest").
    @q            = params[:q].to_s.strip
    @chain        = @project.events.acts.search(@q).latest.includes(:machine, :app).limit(RECORD_HEAD)
                            .map { |e| ChainItem.from_event(e) }
    @record_total = @project.events.count

    # The headline's figures — this client's work, in the words the rest of the app
    # uses. Counted off rows already loaded, and only this lens's facts: what is
    # placed for them, and what of it needs a person.
    @needs_look   = @apps.count(&:needs_a_look?)
    @short        = @apps.count { |i| i.placement_gap.negative? }
    @down_boxes   = (@owned_machines + @shared_machines).count(&:seen_unreachable?)
  end

  private

  # Does this project still serve a (non-retired) app on any box? Deleting it
  # would orphan those running apps, so deletion is refused until they're removed.
  def runs_live_apps?(project)
    Placement.joins(:app)
                 .where(apps: { project_id: project.id })
                 .where.not(status: "retired").exists?
  end

  def project_params
    params.require(:project).permit(:name, :contact_name, :contact_email)
  end
end
