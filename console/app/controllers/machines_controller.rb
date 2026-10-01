class MachinesController < ApplicationController
  before_action :set_machine, only: %i[ show live refresh destroy sharing transfer ]

  # All Machines — the fleet, and the floor of the three rings. This page is about
  # the *shape* of the fleet, so grouping is the primitive rather than filtering: a
  # filter answers one question at a time, a grouping answers all of them at once
  # (see MachineGroups). The old "unowned" toggle is gone — it was one grouping
  # wearing a filter's clothes, and `group=owner` says it better.
  #
  # It states only what this layer owns. No app counts, no project health: a
  # box's page knows nothing about placement or tenancy except the one owner
  # grouping, which is offered rather than assumed (decisions/console-layers.md).
  def index
    @q     = params[:q]
    @group = params[:group].presence || MachineGroups::DEFAULT.key

    machines  = @q.present? ? Machine.search(@q) : Machine.all
    # Everything the row and the groupings read, preloaded: a list must not ask the
    # database once per box any more than it may ask the *boxes* once per row.
    @machines = machines.order(:name)
                        .includes(:owner, :labels, { apps: :balancer },
                                  { fronted_apps: :placements })
    @groups   = MachineGroups.apply(@machines.to_a, @group)

    @label_keys  = MachineGroups.label_keys
    @total       = Machine.count
    @unreachable = Machine.where(status: "unreachable").count
    @never_seen  = Machine.where(status: "unknown").count
  end

  # ── Onboarding (Add Machine) ───────────────────────────────────────────────
  # Register an already-Vilice-ready box: generate Vilice Console's scoped keypair, then
  # surface the `vilice authorize` line to run on it. See machine-onboarding.md.
  def new
    @project  = Project.find_by(id: params[:project_id]) # when adding from a project's app flow
    @projects = Project.order(:name) unless @project     # dropdown to pick an owner (optional)
    @machine  = Machine.new(ssh_user: "_vilice", ssh_port: 22, scope: "operate")
  end

  def create
    @project = Project.find_by(id: params[:project_id])
    # Vilice Console always connects as the _vilice user (scoped keys authenticate as it),
    # so it's not a form choice.
    @machine = Machine.new(machine_params.merge(ssh_user: "_vilice"))
    # The name isn't typed — it mirrors the box. We can't read the box yet (it hasn't
    # authorized our key), so seed it with the SSH host; the first observe renames it to
    # the box's reported hostname (decisions/machine-name-mirrors-the-box.md).
    @machine.name = @machine.ssh_host if @machine.name.blank?
    keys = SshKeypair.generate(comment: "console@#{@machine.name}")
    @machine.ssh_private_key = keys[:private]
    @machine.ssh_public_key  = keys[:public]

    # Owner: the project in the URL (app flow), or the one picked from the dropdown
    # (optional — blank "Unassigned" leaves the box unowned).
    owner = @project || Project.find_by(id: params.dig(:machine, :owner_id).presence)

    if save_recording(@machine, link_to: owner)
      notice = "Added #{@machine.name}. Run the authorize line on the box to connect it."
      redirect_to(@project ? new_app_path(project_id: @project) : @machine, notice: notice)
    else
      @projects = Project.order(:name) unless @project
      render :new, status: :unprocessable_entity
    end
  end

  # The per-machine deep dive, in two requests so the page never waits on the box. `show`
  # is the shell — what we hold ourselves, rendered at once. `live` is everything that
  # needs the box (both zones and the record), loaded into a frame right after, from
  # reads cached for 30s (Decision 3).
  def show
    @q        = params[:q].to_s.strip
    @apps     = @machine.apps.includes(:project).order(:name) # placements on this box (project optional)
    @projects = Project.order(:name) # for the ownership / sharing controls
  end

  # The chain merges the two records — this machine's Vilice Console events (authored)
  # with the box record (witnessed). A box that did not answer the status read is not
  # asked twice more: the record and the ledger would wait out the same timeout.
  def live
    @q      = params[:q].to_s.strip
    @status = MachineStatus.from(Vilice::Observe.status(@machine))
    @record = @status.online? ? Vilice::Observe.record(@machine) : { ok: false, error: @status.error }
    @actors = Vilice::Observe.actors(@machine) if @status.online? # who can reach it
    @chain  = chain_for(@machine, @record).select { |i| i.matches?(@q) }
    @apps   = @machine.apps.includes(:project).order(:name)
    # The edge table this box should serve, derived rather than stored. Empty for a box
    # that isn't a balancer, so the panel simply doesn't render.
    @table  = @machine.balancer? ? @machine.routing_table : []
    render layout: false
  end

  # ── Observe ──────────────────────────────────────────────────────────────
  # Re-read the machine's live status, bypassing the cache. A read: changes
  # nothing on the box.
  def refresh
    Vilice::Observe.status(@machine, refresh: true)
    redirect_to @machine, notice: "Read #{@machine.name} from Vilice."
  end

  # ── Remove ─────────────────────────────────────────────────────────────────
  # Forget this box in the control plane. The box keeps running; this only deletes
  # Vilice Console's record of it (its key stays authorized on the box until revoked
  # there). A recorded own-record act. `events: :nullify` keeps the record intact;
  # the join, targets, snapshots, and labels cascade.
  def destroy
    # Don't let a box that's still serving apps be forgotten — the apps would keep
    # running with the control plane blind to them (decisions/open/status-signals.md).
    # Remove the apps first (or migrate them away, once that verb exists).
    live = @machine.placements.where.not(status: "retired").includes(:app)
    if live.any?
      apps = live.map { |t| t.app.name }.uniq
      return redirect_to @machine,
        alert: "#{@machine.name} still runs #{apps.to_sentence} — remove #{apps.one? ? "that app" : "those apps"} first."
    end

    name = @machine.name
    Machine.transaction do
      @machine.destroy!
      Event.record!(actor: Current.user.email_address, action: "removed",
                    summary: "#{name} from Vilice")
    end
    redirect_to machines_path,
                notice: "Removed #{name}. The box keeps running — revoke Vilice’s key on it to cut access."
  end

  # ── Sharing & ownership (the Access panel) ─────────────────────────────────
  # Set how the box is shared: dedicated (owner only) / everyone / list (owner +
  # allowlist). A recorded own-record act. machine-ownership.md.
  def sharing
    mode = params.require(:machine).permit(:sharing)[:sharing]
    Machine.transaction do
      @machine.update!(sharing: mode)
      Event.record!(actor: Current.user.email_address, action: "set",
                    machine: @machine, summary: "#{@machine.name} sharing to #{mode}")
    end
    redirect_to @machine, notice: "Updated sharing for #{@machine.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @machine, alert: e.message
  end

  # Transfer ownership to another project, or release to no one (unowned). Never a
  # silent change — always this explicit, recorded act. Releasing is what unblocks
  # deleting the former owner. Existing apps are untouched.
  def transfer
    owner = Project.find_by(id: params.dig(:machine, :owner_id).presence)
    Machine.transaction do
      @machine.update!(owner: owner)
      summary = owner ? "#{@machine.name} to #{owner.name}" :
                        "#{@machine.name} — now unowned"
      Event.record!(actor: Current.user.email_address,
                    action: owner ? "transferred" : "released",
                    machine: @machine, project: owner, summary: summary)
    end
    redirect_to @machine, notice: owner ? "Transferred to #{owner.name}." : "Released — now unowned."
  end

  private

  def set_machine
    @machine = Machine.find(params[:id])
  end

  def machine_params
    # No :name — it's not typed; it mirrors the box (seeded from ssh_host, then the
    # box's hostname on first read). See create + observe-reconciliation.
    params.require(:machine).permit(:ssh_host, :ssh_port, :scope)
  end

  # Persist the new machine and record it atomically, optionally linking it to a
  # project — which then *owns* the box (the common case: you register a box for a
  # client from their app flow). A fleet-registered box (no project) is born
  # unowned, surfaced on the machines page. Report invalid on failure.
  def save_recording(machine, link_to: nil)
    Machine.transaction do
      machine.owner = link_to if link_to
      machine.save!
      ProjectMachine.create!(project: link_to, machine: machine) if link_to
      summary = "#{machine.name} (#{machine.scope})"
      summary += " to #{link_to.name}" if link_to
      Event.record!(actor: Current.user.email_address, action: "added",
                    machine: machine, project: link_to, summary: summary)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    @machine.errors.add(:base, e.message) if @machine.errors.empty?
    false
  end

  # Merge the two records into one newest-first timeline: this machine's
  # Vilice Console events (authored) + the box's own record (witnessed, unless our
  # own client issued it). See Chain and decisions/two-records.md.
  def chain_for(machine, record)
    events = machine.events.acts.latest.includes(:project, :app).limit(40)
    Chain.for_machine(events, record.dig(:data, "data", "entries") || [],
                      client: ENV.fetch("VILICE_CLIENT_NAME", "console"))
  end
end
