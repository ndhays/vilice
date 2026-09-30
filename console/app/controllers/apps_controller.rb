# Place an app on a box — the placement layer (decisions/console-layers.md). An App
# says *what should run where*; a Project, when there is one, says whose work it is.
# Tenancy is optional here, so a project arrives as `?project_id=` context and narrows
# the machine list; with none, you place onto any operate-scoped box in the fleet.
#
# Pick a library app (deploys its latest version) or, when the library-only setting is
# off, a custom image. Set up the App + Placement records, then hand off to the
# witnessed deploy ceremony. Setting up is a control-plane own-record act; the deploy
# stays witnessed.
class AppsController < ApplicationController
  before_action :set_project

  # Every placement in the fleet, tenant or no tenant. The project column is the lens
  # onto tenancy — blank where there isn't one, which is a legitimate state, not a gap.
  #
  # Searched and grouped like the fleet list: one `?q=` over what identifies a
  # placement, and `?group=` over the axes it actually has. Both live in the query
  # string, so a narrowed list is a link you can send.
  def index
    @q     = params[:q]
    @group = params[:group].presence || AppGroups::DEFAULT.key

    apps  = @q.present? ? App.search(@q) : App.all
    # Everything the row and the groupings read, preloaded: a list must not ask the
    # database once per row. `placements: :machine` carries `App#state`,
    # which walks the targets and their boxes.
    @apps = apps.order(:name)
                        .includes(:app_template, :version, :project, :balancer,
                                  placements: :machine)
    rows      = @apps.to_a
    @groups   = AppGroups.apply(rows, @group)
    @total    = App.count
    # The headline's two figures, counted off the rows already loaded.
    @needs_look = rows.count(&:needs_a_look?)
    @short      = rows.count { |i| i.placement_gap.negative? }
  end

  def new
    @app = App.new(project: @project)
    load_form
  end

  # The App deep-dive — the app-actions home (decisions/install-the-app-actions-home.md).
  # State, what's deployed where (with drift), and the witnessed verbs per live target.
  def show
    @app = App.find(params[:id])
    @project = @app.project
    @placements = @app.placements.includes(:machine).where.not(status: "retired").order(:id)
    @q       = params[:q].to_s.strip
    @chain   = @app.events.acts.search(@q).latest.includes(:machine, :app).limit(20)
                       .map { |e| ChainItem.from_event(e) }
  end

  # Restate the intention — how many boxes, and how it's reached. Deliberately narrow:
  # this edits what was *asked for*, not what gets deployed. The spec (image, name,
  # volumes) is a different concern and is not reachable here.
  def edit
    @app = App.find(params[:id])
  end

  # Saying "three boxes" instead of "one" opens a gap. It does not deploy anything, and
  # saying "one" instead of "three" does not remove anything — a cascade of destructive
  # calls whose only trace is a changed number is exactly what
  # decisions/drift-is-surfaced-never-closed.md refuses. The gap simply moves, and closing
  # it either way stays a named act.
  def update
    @app = App.find(params[:id])
    before = intention_of(@app)

    if @app.update(intention_attrs)
      record_restated(before)
      redirect_to @app, notice: "Intention updated. Nothing was deployed or removed."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # **An app is an intention, and an intention does not need a box.** Requiring one
  # here made the claim depend on the reality it is supposed to be compared against —
  # the exact merge decisions/drift-is-surfaced-never-closed.md keeps apart. So the box
  # is optional: with none, this writes the intention and lands on a page showing the
  # gap it just opened, which is a state the model, the list and the badges already knew
  # how to render and only this form refused to create.
  #
  # The spec is still required. "Deploy something, we'll decide what later" is not an
  # intention, it is a blank.
  def create
    @app = App.new(app_attrs.merge(project: @project))
    # Blank and refused are different answers. Leaving the box out is the new legal
    # path; naming one this app may not land on is a request we are not honouring,
    # and quietly creating an unplaced app instead would drop it in silence.
    picked   = params.dig(:app, :machine_id).presence
    @machine = placeable_machines.find_by(id: picked) if picked

    @app.errors.add(:base, "Pick an app (or a custom image).") if @app.image.blank?
    @app.errors.add(:base, no_machine_message) if picked && @machine.nil?

    # Short-circuit: nothing is written while an answer is missing or refused.
    if @app.errors.any? || !save_app
      load_form
      return render :new, status: :unprocessable_entity
    end

    # With a box, straight on to the witnessed deploy as before. Without one, the app
    # page — where the gap this just opened is already rendered, and where the act that
    # closes it lives. Not an error page and not a dead end: a stated intention, which is
    # a complete thing on its own.
    if @machine
      redirect_to new_machine_mutation_path(@machine, act: "deploy", app_id: @app.id)
    else
      redirect_to @app, notice: "Added #{@app.name}. Nothing is deployed yet — " \
                                    "place it on a box, which is a recorded act."
    end
  end

  # Supply the values behind the names the app declares. Separate from `update` on
  # purpose: that one restates the intention and reaches nothing deployable, while this
  # is the app's configuration and the one door a secret value comes through.
  #
  # **Nothing here is recorded.** A plain env value is part of the spec and will be
  # recorded when it is deployed; a secret rides stdin and never is. Saving them is not
  # itself an act on a box — nothing is deployed until the witnessed ceremony runs — so
  # it writes no chain entry, the same reasoning as `a-sample-is-not-an-act.md`: this
  # reports that something was configured, not that anything happened.
  def configure
    @app = App.find(params[:id])

    # Blank means "leave it alone", never "clear it". A password field renders empty by
    # design — the stored value is never sent back to the page — so treating an empty
    # box as a deletion would wipe every secret you did not retype.
    supplied = params.fetch(:app, {}).fetch(:secret_values, {}).to_unsafe_h
                     .select { |_, v| v.to_s.present? }
    @app.secret_values = @app.secret_values.merge(supplied)

    env = params.fetch(:app, {}).fetch(:env, {}).to_unsafe_h
    @app.config = @app.config.merge("env" => env.compact_blank) if env.any?

    if @app.save
      redirect_to @app, notice: configure_notice(supplied)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def configure_notice(supplied)
    left = @app.missing_secrets
    saved = "Saved#{" #{supplied.size} #{'value'.pluralize(supplied.size)}" if supplied.any?}."
    return "#{saved} Nothing was deployed — that is still an act." if left.empty?

    "#{saved} Still needed: #{left.join(', ')}."
  end

  # Optional context, never a form field: the project is in the URL or it isn't
  # (blueprint/console/journeys.md). Nothing here asks you to invent one.
  def set_project
    @project = Project.find_by(id: params[:project_id])
  end

  # Where this app may land. Under a project, its own boxes — the sharing rules
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
    lead = @project ? "That box isn't on this project" : "That box isn't one this app can use"
    "#{lead} — pick another, or leave it blank and place it later."
  end

  def allow_custom? = !Setting.current.apps_library_only

  def load_form
    @app_templates         = AppTemplate.where.associated(:latest_version).includes(:versions, :labels).order(:name)
    @machines     = placeable_machines.operate.order(:name)
    @allow_custom = allow_custom?
  end

  # Resolve the app's spec from the form: a custom image (when allowed) or a library
  # app at a chosen version (default the app's latest). Template-derived fields fill in any the
  # operator left blank.
  def app_attrs
    p = params.require(:app).permit(:name, :hostname, :port, :health, :image, :app_template_id,
                                        :version_id, :volumes, :count, :exposure, :balancer_id)
    config = build_config(p)
    # The intention. Blank means the single-box default on its own edge, not zero.
    count    = p[:count].presence || 1
    exposure = p[:exposure].presence || "edge"

    if allow_custom? && p[:app_template_id].blank? && p[:image].present?
      { name: p[:name], hostname: p[:hostname], port: p[:port], health: p[:health],
        image: p[:image], config: config, count: count, exposure: exposure,
        balancer_id: p[:balancer_id].presence }
    else
      template     = AppTemplate.find_by(id: p[:app_template_id])
      # The version must belong to the chosen app; fall back to its latest.
      version = template&.versions&.find_by(id: p[:version_id]) || template&.latest_version
      { app_template: template, version: version, image: version&.image,
        name: p[:name].presence || template&.name, hostname: p[:hostname],
        port: p[:port].presence || template&.port, health: p[:health].presence || template&.health,
        config: config, count: count, exposure: exposure,
        balancer_id: p[:balancer_id].presence }
    end
  end

  # Volumes arrive as a textarea, one `name:/path` mount per line. They live in the
  # App's `config` blob — the same desired-state the deploy envelope reads.
  # The app's own copy of the declared spec. Volumes are typed here; the release
  # command is **copied from the App at create** rather than read at deploy time, so
  # editing the library later never silently changes what an already-placed app runs.
  # Same reason the image is copied from the Version instead of followed.
  def build_config(p)
    config  = {}
    volumes = p[:volumes].to_s.split("\n").map(&:strip).reject(&:blank?)
    config["volumes"] = volumes if volumes.any?

    if (template = AppTemplate.find_by(id: p[:app_template_id]))
      config["release"]     = template.release if template.release.present?
      config["accessories"] = template.accessories if template.accessories.present?
      config["processes"]   = template.processes if template.processes.present?
    end
    config
  end

  # Two decisions, two records. Declaring what should run is `added app` and reaches
  # nothing; landing it on a box is `placed app`, the same verb the standalone
  # placement door records. Choosing a box on this form does both at once, so it writes
  # both — one act standing for two different decisions was the anomaly, and it meant
  # the two doors into a placement disagreed about what to call it.
  def save_app
    App.transaction do
      @app.save!
      Event.record!(actor: Current.user.email_address, action: "added",
                    project: @project, app: @app, summary: added_summary)
      @app.place_on!(@machine, actor: Current.user.email_address) if @machine
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    @app.errors.add(:base, e.message) if @app.errors.empty?
    false
  end

  def added_summary
    @project ? "#{@app.name} to #{@project.name}" : @app.name
  end

  # Only the intention. `count` and `exposure` and nothing else — a spec change would ride
  # in on the same form otherwise, and this act is recorded as a restatement of intent.
  def intention_attrs
    params.require(:app).permit(:count, :exposure, :balancer_id)
  end

  def intention_of(app)
    where = app.balancer ? " behind #{app.balancer.name}" : ""
    "#{app.count} #{'box'.pluralize(app.count)}, #{app.exposure}#{where}"
  end

  # Restating what you asked for is a control-plane act with no box behind it — recorded
  # with human attribution and no outcome to settle, like a label edit or a star.
  def record_restated(before)
    after = intention_of(@app)
    return if before == after

    Event.record!(
      actor: Current.user.email_address, action: "restated",
      project: @app.project, app: @app,
      summary: "#{@app.name}: asked for #{before} → #{after}"
    )
  end
end
