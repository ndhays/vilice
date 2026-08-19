# Place an app on a box — the placement layer (decisions/console-layers.md). An Install
# says *what should run where*; a Project, when there is one, says whose work it is.
# Tenancy is optional here, so a project arrives as `?project_id=` context and narrows
# the machine list; with none, you place onto any operate-scoped box in the fleet.
#
# Pick a library app (deploys its latest version) or, when the library-only setting is
# off, a custom image. Set up the Install + InstallTarget records, then hand off to the
# witnessed deploy ceremony. Setting up is a control-plane own-record act; the deploy
# stays witnessed.
class InstallsController < ApplicationController
  before_action :set_project

  # Every placement in the fleet, tenant or no tenant. The project column is the lens
  # onto tenancy — blank where there isn't one, which is a legitimate state, not a gap.
  #
  # Searched and grouped like the fleet list: one `?q=` over what identifies a
  # placement, and `?group=` over the axes it actually has. Both live in the query
  # string, so a narrowed list is a link you can send.
  def index
    @q     = params[:q]
    @group = params[:group].presence || InstallGroups::DEFAULT.key

    installs  = @q.present? ? Install.search(@q) : Install.all
    # Everything the row and the groupings read, preloaded: a list must not ask the
    # database once per row. `install_targets: :machine` carries `Install#state`,
    # which walks the targets and their boxes.
    @installs = installs.order(:name)
                        .includes(:app, :version, :project, :balancer,
                                  install_targets: :machine)
    rows      = @installs.to_a
    @groups   = InstallGroups.apply(rows, @group)
    @total    = Install.count
    # The headline's two figures, counted off the rows already loaded.
    @needs_look = rows.count(&:needs_a_look?)
    @short      = rows.count { |i| i.placement_gap.negative? }
  end

  def new
    @install = Install.new(project: @project)
    load_form
  end

  # The Install deep-dive — the app-actions home (decisions/install-the-app-actions-home.md).
  # State, what's deployed where (with drift), and the witnessed verbs per live target.
  def show
    @install = Install.find(params[:id])
    @project = @install.project
    @targets = @install.install_targets.includes(:machine).where.not(status: "retired").order(:id)
    @q       = params[:q].to_s.strip
    @chain   = @install.events.acts.search(@q).latest.includes(:machine, :install).limit(20)
                       .map { |e| ChainItem.from_event(e) }
  end

  # Restate the intention — how many boxes, and how it's reached. Deliberately narrow:
  # this edits what was *asked for*, not what gets deployed. The spec (image, name,
  # volumes) is a different concern and is not reachable here.
  def edit
    @install = Install.find(params[:id])
  end

  # Saying "three boxes" instead of "one" opens a gap. It does not deploy anything, and
  # saying "one" instead of "three" does not remove anything — a cascade of destructive
  # calls whose only trace is a changed number is exactly what
  # decisions/drift-is-surfaced-never-closed.md refuses. The gap simply moves, and closing
  # it either way stays a named act.
  def update
    @install = Install.find(params[:id])
    before = intention_of(@install)

    if @install.update(intention_attrs)
      record_restated(before)
      redirect_to @install, notice: "Intention updated. Nothing was deployed or removed."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # **An install is an intention, and an intention does not need a box.** Requiring one
  # here made the claim depend on the reality it is supposed to be compared against —
  # the exact merge decisions/drift-is-surfaced-never-closed.md keeps apart. So the box
  # is optional: with none, this writes the intention and lands on a page showing the
  # gap it just opened, which is a state the model, the list and the badges already knew
  # how to render and only this form refused to create.
  #
  # The spec is still required. "Deploy something, we'll decide what later" is not an
  # intention, it is a blank.
  def create
    @install = Install.new(install_attrs.merge(project: @project))
    # Blank and refused are different answers. Leaving the box out is the new legal
    # path; naming one this install may not land on is a request we are not honouring,
    # and quietly creating an unplaced install instead would drop it in silence.
    picked   = params.dig(:install, :machine_id).presence
    @machine = placeable_machines.find_by(id: picked) if picked

    @install.errors.add(:base, "Pick an app (or a custom image).") if @install.image.blank?
    @install.errors.add(:base, no_machine_message) if picked && @machine.nil?

    # Short-circuit: nothing is written while an answer is missing or refused.
    if @install.errors.any? || !save_install
      load_form
      return render :new, status: :unprocessable_entity
    end

    # With a box, straight on to the witnessed deploy as before. Without one, the install
    # page — where the gap this just opened is already rendered, and where the act that
    # closes it lives. Not an error page and not a dead end: a stated intention, which is
    # a complete thing on its own.
    if @machine
      redirect_to new_machine_mutation_path(@machine, act: "deploy", install_id: @install.id)
    else
      redirect_to @install, notice: "Added #{@install.name}. Nothing is deployed yet — " \
                                    "place it on a box, which is a recorded act."
    end
  end

  private

  # Optional context, never a form field: the project is in the URL or it isn't
  # (blueprint/console/journeys.md). Nothing here asks you to invent one.
  def set_project
    @project = Project.find_by(id: params[:project_id])
  end

  # Where this install may land. Under a project, its own boxes — the sharing rules
  # already decided which those are. With no project, the whole fleet, which is the
  # point of the inversion. The form offers only operate-scoped boxes (an observe key
  # can't deploy), but an existing target may sit on a box since downgraded, so the
  # scope filter belongs on the picker, not on the set.
  def placeable_machines
    @project&.machines || Machine.all
  end

  # Only ever shown for a box that was named and refused — never for a blank one, which
  # is now a legitimate answer. So it says why that box, and what the ways out are.
  def no_machine_message
    lead = @project ? "That box isn't on this project" : "That box isn't one this install can use"
    "#{lead} — pick another, or leave it blank and place it later."
  end

  def allow_custom? = !Setting.current.installs_library_only

  def load_form
    @apps         = App.where.associated(:latest_version).includes(:versions, :labels).order(:name)
    @machines     = placeable_machines.operate.order(:name)
    @allow_custom = allow_custom?
  end

  # Resolve the install's spec from the form: a custom image (when allowed) or a library
  # app at a chosen version (default the app's latest). App-derived fields fill in any the
  # operator left blank.
  def install_attrs
    p = params.require(:install).permit(:name, :hostname, :port, :health, :image, :app_id,
                                        :version_id, :volumes, :count, :exposure, :balancer_id)
    config = build_config(p)
    # The intention. Blank means the single-box default on its own edge, not zero.
    count    = p[:count].presence || 1
    exposure = p[:exposure].presence || "edge"

    if allow_custom? && p[:app_id].blank? && p[:image].present?
      { name: p[:name], hostname: p[:hostname], port: p[:port], health: p[:health],
        image: p[:image], config: config, count: count, exposure: exposure,
        balancer_id: p[:balancer_id].presence }
    else
      app     = App.find_by(id: p[:app_id])
      # The version must belong to the chosen app; fall back to its latest.
      version = app&.versions&.find_by(id: p[:version_id]) || app&.latest_version
      { app: app, version: version, image: version&.image,
        name: p[:name].presence || app&.name, hostname: p[:hostname],
        port: p[:port].presence || app&.port, health: p[:health].presence || app&.health,
        config: config, count: count, exposure: exposure,
        balancer_id: p[:balancer_id].presence }
    end
  end

  # Volumes arrive as a textarea, one `name:/path` mount per line. They live in the
  # Install's `config` blob — the same desired-state the deploy envelope reads.
  # The install's own copy of the declared spec. Volumes are typed here; the release
  # command is **copied from the App at create** rather than read at deploy time, so
  # editing the library later never silently changes what an already-placed app runs.
  # Same reason the image is copied from the Version instead of followed.
  def build_config(p)
    config  = {}
    volumes = p[:volumes].to_s.split("\n").map(&:strip).reject(&:blank?)
    config["volumes"] = volumes if volumes.any?

    release = App.find_by(id: p[:app_id])&.release
    config["release"] = release if release.present?
    config
  end

  # Two decisions, two records. Declaring what should run is `added install` and reaches
  # nothing; landing it on a box is `placed install`, the same verb the standalone
  # placement door records. Choosing a box on this form does both at once, so it writes
  # both — one act standing for two different decisions was the anomaly, and it meant
  # the two doors into a placement disagreed about what to call it.
  def save_install
    Install.transaction do
      @install.save!
      Event.record!(actor: Current.user.email_address, action: "added",
                    project: @project, install: @install, summary: added_summary)
      @install.place_on!(@machine, actor: Current.user.email_address) if @machine
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    @install.errors.add(:base, e.message) if @install.errors.empty?
    false
  end

  def added_summary
    @project ? "#{@install.name} to #{@project.name}" : @install.name
  end

  # Only the intention. `count` and `exposure` and nothing else — a spec change would ride
  # in on the same form otherwise, and this act is recorded as a restatement of intent.
  def intention_attrs
    params.require(:install).permit(:count, :exposure, :balancer_id)
  end

  def intention_of(install)
    where = install.balancer ? " behind #{install.balancer.name}" : ""
    "#{install.count} #{'box'.pluralize(install.count)}, #{install.exposure}#{where}"
  end

  # Restating what you asked for is a control-plane act with no box behind it — recorded
  # with human attribution and no outcome to settle, like a label edit or a star.
  def record_restated(before)
    after = intention_of(@install)
    return if before == after

    Event.record!(
      actor: Current.user.email_address, action: "restated",
      project: @install.project, install: @install,
      summary: "#{@install.name}: asked for #{before} → #{after}"
    )
  end
end
