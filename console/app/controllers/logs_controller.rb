# An app's logs, read off the box on request.
#
# **A read, not an act.** Nothing is recorded, because nothing happened: `steward logs`
# is `observe` scope and a passthrough to `podman logs`
# (decisions/a-sample-is-not-an-act.md — an act reports that something happened, and
# looking is not that). It is also the only observe read that mirrors nothing into our
# own columns; there is no projection to keep, just an answer to a question.
#
# **Pulled, never rendered by default.** Every tail is an SSH round trip, so it lives
# behind its own request rather than inside the install page — the same rule that keeps
# a list from asking the database once per row applies harder to asking a *box*.
class LogsController < ApplicationController
  def show
    @machine = Machine.find(params[:machine_id])
    @install = Install.find(params[:install_id])
    @tail    = Steward::Observe::TAILS.include?(params[:tail].to_i) ? params[:tail].to_i
                                                                   : Steward::Observe::DEFAULT_TAIL
    # The app is only readable where it was actually placed. Asking box B for app A's
    # logs when A lives on C would fail on the box anyway; refusing here says why.
    @target = @install.install_targets.find_by(machine: @machine)
    return render :absent, status: :not_found unless @target

    @result = Steward::Observe.logs(@machine, @install.name, tail: @tail)
  end
end
