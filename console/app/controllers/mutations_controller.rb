# The mutate ceremony — the one generic flow for any witnessed, operate-scoped
# act (decisions/open/ui-shape.md §"the mutate ceremony"):
#
#   new    — compose (if the act needs input), then preview the exact record line.
#            No DB write.
#   create — record it pending, issue it over scoped SSH (the deploy envelope rides
#            stdin), settle the outcome, and reconcile control-plane state.
#
# The verb is always resolved through Mutation's allowlist, never trusted raw.
class MutationsController < ApplicationController
  before_action :set_machine
  before_action :set_mutation
  before_action :set_return

  # Compose the act (deploy needs an image digest), else preview it.
  def new
    render :compose if @mutation.needs_compose? && !@mutation.composed?
  end

  # Confirm/execute. Operate-scoped only; an observe key can't act (Invariant 1).
  def create
    unless @machine.operate?
      return redirect_to @return_path,
        alert: "#{@machine.name} holds only an observe key — mutation needs operate."
    end
    # A compose act reaching create without its input is a malformed request.
    return redirect_to(new_machine_mutation_path(@machine, act: @mutation.act.verb,
      install_id: @mutation.install&.id, from: @from)) unless @mutation.composed?

    outcome = Steward::Mutate.run(
      @machine, @mutation.command,
      actor: Current.user.email_address, action: @mutation.action,
      install: @mutation.install, summary: @mutation.summary, stdin: @mutation.stdin
    )

    reconcile(outcome) if outcome[:result][:ok]

    if outcome[:result][:ok]
      redirect_to @return_path, notice: "#{@mutation.summary.upcase_first} (witnessed)."
    else
      redirect_to @return_path, alert: "#{@mutation.act.label} failed: #{outcome[:result][:error]}"
    end
  end

  private

  def set_machine
    @machine = Machine.find(params[:machine_id])
  end

  # Where the ceremony returns when it settles or is cancelled. The act is always
  # keyed to a machine (the SSH target), but it can be launched from the install
  # page or the machine page — `from` says which, so we land back where we started.
  # See decisions/install-the-app-actions-home.md.
  def set_return
    @from = params[:from].presence
    @return_path =
      if @from == "install" && @mutation.install
        install_path(@mutation.install)
      else
        machine_path(@machine)
      end
  end

  # Bind the requested verb (+ install + compose params) to a runnable act, or bail.
  def set_mutation
    @mutation = Mutation.build(
      params[:act], machine: @machine, actor: Current.user.email_address,
      install_id: params[:install_id], params: compose_params
    )
    redirect_to @machine, alert: "Unknown or invalid act." unless @mutation
  end

  def compose_params
    params.permit(:image, :hostname, :port, :health).to_h.symbolize_keys
  end

  # Reconcile control-plane state after a successful act. Deploy pins the desired
  # image (current_image stays observe-reconciled — honest drift). Remove retires
  # the target (the app is off the box; the row stays for history).
  def reconcile(outcome)
    target = @mutation.install&.install_targets&.find_by(machine: @machine)
    return unless target

    case @mutation.act.verb
    when "deploy" then target.update(desired_image: @mutation.image, status: "running")
    when "remove" then target.update(status: "retired")
    end
  end
end
