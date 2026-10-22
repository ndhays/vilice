# Log a box into a private image registry.
#
# A registry login is a box credential, not part of any app
# (decisions/registry-credentials.md), so it is set from the machine page. It is not a
# ceremony act because it carries a password, and the ceremony's preview travels in a
# URL. Here the form is the preview: it shows the command, and says what is recorded.
#
# The password goes to the box on stdin and is kept nowhere — not in a column, not in
# the Event, not in a log (`password` is a filtered parameter). The console holds no
# registry credential afterwards; the box does.
class Machines::RegistriesController < ApplicationController
  before_action :set_machine
  before_action :require_operate

  def new
    @registry = params[:registry].to_s
  end

  def create
    @registry = params[:registry].to_s.strip
    @username = params[:username].to_s.strip
    password  = params[:password].to_s

    @error = problem(@registry, @username, password)
    return render :new, status: :unprocessable_entity if @error

    outcome = Vilice::Mutate.run(
      @machine, "registry-login #{@registry} --username #{@username} --json",
      actor: Current.user.email_address, action: "logged in",
      summary: "#{@machine.name} to #{@registry} as #{@username}",
      stdin: password
    )

    if outcome[:result][:ok]
      redirect_to status_machine_path(@machine, anchor: "registries"), notice: "Logged #{@machine.name} in to #{@registry}."
    else
      @error = outcome[:result][:error]
      render :new, status: :unprocessable_entity
    end
  end

  private

  # A username is written into the command, so it may hold nothing that would split
  # it or read as a flag. The box checks the registry again.
  USERNAME_FORMAT = /\A[A-Za-z0-9_][A-Za-z0-9_.@+-]*\z/

  def problem(registry, username, password)
    return "Name the registry as a host, like ghcr.io — no path and no spaces." unless registry.match?(Mutation::REGISTRY_FORMAT)
    return "The username may hold letters, digits and . _ @ + - only." unless username.match?(USERNAME_FORMAT)
    "Give the password or token." if password.blank?
  end

  def set_machine = @machine = Machine.find(params[:machine_id])

  def require_operate
    redirect_to @machine, alert: "This machine's key is observe-only." unless @machine.operate?
  end
end
