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
    # A declared secret with no value is refused by the box, every time — so this is a
    # certainty rather than a guess, and refusing here costs nothing. Unlike the
    # authorize gap (a *reading* that can be stale, so it only warns), we either hold a
    # value or we do not. Refused before the Event is written, the same shape as the
    # observe-scope refusal above: nothing was attempted, so nothing is recorded.
    if @mutation.act.verb == "deploy" && (missing = @mutation.app&.missing_secrets).present?
      return redirect_to @return_path,
        alert: "#{@mutation.app.name} needs #{'a value'.pluralize(missing.size)} for " \
               "#{missing.join(', ')} — the box refuses a deploy without one. " \
               "Set them under Configuration."
    end
    # A compose act reaching create without its input is a malformed request.
    return redirect_to(new_machine_mutation_path(@machine, act: @mutation.act.verb,
      app_id: @mutation.app&.id, from: @from)) unless @mutation.composed?

    outcome = Steward::Mutate.run(
      @machine, @mutation.command,
      actor: Current.user.email_address, action: @mutation.action,
      app: @mutation.app, summary: @mutation.summary, stdin: @mutation.stdin
    )

    reconcile(outcome) if outcome[:result][:ok]

    if outcome[:result][:ok]
      redirect_to @return_path, notice: "#{@mutation.summary.upcase_first} (witnessed)."
    else
      redirect_to @return_path, alert: failure_alert(outcome[:result])
    end
  end

  private

  # The act was recorded and it failed — that much is honest and stays. What the raw
  # transport error does not say is *which* failure this was: a box that refused the act
  # and a box we never got to look nothing alike and are fixed nowhere near each other.
  # When ssh itself could not get through, the box's own diagnosis is appended.
  def failure_alert(result)
    base = "#{@mutation.act.label} failed: #{result[:error]}"
    result[:reached] == false ? "#{base} — #{@machine.connection_hint}" : base
  end

  def set_machine
    @machine = Machine.find(params[:machine_id])
  end

  # Where the ceremony returns when it settles or is cancelled. The act is always
  # keyed to a machine (the SSH target), but it can be launched from the app
  # page or the machine page — `from` says which, so we land back where we started.
  # See decisions/install-the-app-actions-home.md.
  def set_return
    @from = params[:from].presence
    @return_path =
      if @from == "app" && @mutation.app
        app_path(@mutation.app)
      else
        machine_path(@machine)
      end
  end

  # Bind the requested verb (+ app + compose params) to a runnable act, or bail.
  def set_mutation
    @mutation = Mutation.build(
      params[:act], machine: @machine, actor: Current.user.email_address,
      app_id: params[:app_id], params: compose_params
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
    placement = @mutation.app&.placements&.find_by(machine: @machine)
    return unless placement

    case @mutation.act.verb
    when "deploy" then placement.update(desired_image: @mutation.image, status: "running")
    when "remove" then placement.update(status: "retired")
    end
  end
end
