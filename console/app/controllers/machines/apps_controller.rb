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

  def new
    @name = params[:name]
  end

  def create
    name   = params[:name].to_s.strip
    config = params[:config].to_s

    spec, error = parse_config(name, config)
    if error
      @name, @config, @error = name, config, error
      return render :new, status: :unprocessable_entity
    end

    outcome = Steward::Mutate.run(
      @machine, Mutation.command("deploy", @machine, name: name),
      actor: Current.user&.email_address || "console",
      action: "deployed",
      summary: "#{name} on #{@machine.name}",
      stdin: spec.to_json
    )

    if outcome[:result][:ok]
      redirect_to @machine, notice: "Deployed #{name}."
    else
      @name, @config, @error = name, config, outcome[:result][:error]
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    name = params[:id].to_s
    outcome = Steward::Mutate.run(
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
    return unless MachineStatus.from(Steward::Observe.status(@machine)).balancer?

    redirect_to @machine, alert: "This box is a balancer — it fronts other boxes and runs no apps."
  end

  # Validate only what we must: that it is JSON, that it is an object, and that the
  # name we are deploying under matches. Everything else is the box's to judge —
  # it validates the spec at the render boundary and refuses what it cannot render,
  # and duplicating those rules here would give two answers that drift apart.
  def parse_config(name, config)
    return [ nil, "Name is required." ] if name.blank?
    return [ nil, "Paste the app's config." ] if config.blank?

    spec = JSON.parse(config)
    return [ nil, "The config must be a JSON object." ] unless spec.is_a?(Hash)

    # The box keys state by the name it is given; a spec naming something else would
    # deploy under one name and describe another.
    if spec["name"].present? && spec["name"] != name
      return [ nil, %(The config names "#{spec['name']}" but you are deploying "#{name}".) ]
    end

    [ spec.merge("name" => name), nil ]
  rescue JSON::ParserError => e
    [ nil, "That is not valid JSON: #{e.message.truncate(120)}" ]
  end
end
