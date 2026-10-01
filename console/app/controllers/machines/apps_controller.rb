# Apps on one box, as the box sees them.
#
# This is the machine view's deploy surface, and it is deliberately **stateless in the
# console**: no App row, no stored AppConfig, no Project. The config is transit —
# it is sent to the box on stdin and discarded. What happened afterwards is read back
# from the box, whose record is the only record.
#
# That is not a limitation, it is the point. A stored copy of the spec would be a
# second, quieter answer to "what is supposed to be running here" — which is exactly
# the intention layer's job, one ring out, where drift against reality is visible
# rather than assumed away.
class Machines::AppsController < ApplicationController
  before_action :set_machine
  before_action :require_operate
  before_action :require_host_role

  # The form. `template_id` prefills it from an App Template; the choice is a plain GET,
  # so picking one is a link, not a script.
  def new
    template = AppTemplate.find_by(id: params[:template_id])
    @deploy = template ? BoxDeploy.from_template(template, name: params[:name]) : BoxDeploy.new(name: params[:name])
    @templates = AppTemplate.where.associated(:latest_version).order(:name)
  end

  # Two steps, one action. Without `confirm` it is the preview: the plain reading, the
  # command, and the exact envelope, with nothing sent. With it, the act — recorded, then
  # run. `edit` goes back to the form with everything still filled in.
  def create
    @deploy = BoxDeploy.new(deploy_params)
    @templates = AppTemplate.where.associated(:latest_version).order(:name)
    return render :new if params[:edit].present?
    return render :new, status: :unprocessable_entity unless @deploy.valid?
    return render :preview unless params[:confirm].present?

    outcome = Vilice::Mutate.run(
      @machine, @deploy.command,
      actor: Current.user&.email_address || "console",
      action: "deployed",
      summary: "#{@deploy.name} on #{@machine.name}",
      stdin: @deploy.envelope.to_json
    )

    if outcome[:result][:ok]
      redirect_to @machine, notice: "Deployed #{@deploy.name}."
    else
      @error = outcome[:result][:error]
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    name = params[:id].to_s
    outcome = Vilice::Mutate.run(
      @machine, Mutation.command("remove", @machine, name: name),
      actor: Current.user&.email_address || "console",
      action: "removed",
      summary: "#{name} from #{@machine.name}"
    )
    if outcome[:result][:ok]
      redirect_to @machine, notice: "Removed #{name}."
    else
      redirect_to @machine, alert: "Could not remove #{name}: #{outcome[:result][:error]}"
    end
  end

  private

  def set_machine = @machine = Machine.find(params[:machine_id])

  # Buttons follow the key, not the role: a box whose key carries `observe` has no
  # deploy surface at all. The box would refuse it anyway — this is so we do not
  # offer what cannot happen.
  def require_operate
    redirect_to @machine, alert: "This machine's key is observe-only." unless @machine.operate?
  end

  # And no deploy surface on a box whose role is not to run apps. Not disabled —
  # absent, because a balancer genuinely cannot deploy: it has no container runtime,
  # and the box would refuse the verb by name.
  #
  # An unreachable or unprepared box reports no role at all, and that reads as
  # *unknown*, not as *balancer* — we do not take a surface away on a guess. The box
  # is the one that refuses, and it will.
  def require_host_role
    return unless MachineStatus.from(Vilice::Observe.status(@machine)).balancer?

    redirect_to @machine, alert: "This box is a balancer — it fronts other boxes and runs no apps."
  end

  def deploy_params
    params.fetch(:box_deploy, {}).permit(:name, :image, :hostnames, :port, :health, :env,
                                         :secrets, :volumes, :extras, :pasted, :template_id)
  end
end
