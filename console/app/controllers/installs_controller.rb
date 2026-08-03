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
  def index
    @installs = Install.includes(:app, :version, :project, install_targets: :machine)
                       .order(:name)
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
    @chain   = @install.events.latest.includes(:machine, :install).limit(20)
                       .map { |e| ChainItem.from_event(e) }
  end

  def create
    @install = Install.new(install_attrs.merge(project: @project))
    @machine = placeable_machines.find_by(id: params.dig(:install, :machine_id))

    if @machine && @install.image.present? && place_install
      redirect_to new_machine_mutation_path(@machine, act: "deploy", install_id: @install.id)
    else
      @install.errors.add(:base, no_machine_message) unless @machine
      @install.errors.add(:base, "Pick an app (or a custom image).") if @install.image.blank?
      load_form
      render :new, status: :unprocessable_entity
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

  def no_machine_message
    @project ? "Pick a machine on this project." : "Pick a machine."
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
    p = params.require(:install).permit(:name, :hostname, :port, :health, :image, :app_id, :version_id, :volumes)
    config = build_config(p)

    if allow_custom? && p[:app_id].blank? && p[:image].present?
      { name: p[:name], hostname: p[:hostname], port: p[:port], health: p[:health],
        image: p[:image], config: config }
    else
      app     = App.find_by(id: p[:app_id])
      # The version must belong to the chosen app; fall back to its latest.
      version = app&.versions&.find_by(id: p[:version_id]) || app&.latest_version
      { app: app, version: version, image: version&.image,
        name: p[:name].presence || app&.name, hostname: p[:hostname],
        port: p[:port].presence || app&.port, health: p[:health].presence || app&.health,
        config: config }
    end
  end

  # Volumes arrive as a textarea, one `name:/path` mount per line. They live in the
  # Install's `config` blob — the same desired-state the deploy envelope reads.
  def build_config(p)
    volumes = p[:volumes].to_s.split("\n").map(&:strip).reject(&:blank?)
    volumes.any? ? { "volumes" => volumes } : {}
  end

  def place_install
    Install.transaction do
      @install.save!
      @install.install_targets.create!(machine: @machine, status: "pending")
      Event.record!(
        actor: Current.user.email_address, action: "added install",
        project: @project, install: @install, machine: @machine,
        summary: placement_summary
      )
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    @install.errors.add(:base, e.message) if @install.errors.empty?
    false
  end

  def placement_summary
    where = @project ? " to #{@project.name}" : ""
    "Added #{@install.name}#{where} on #{@machine.name}"
  end
end
