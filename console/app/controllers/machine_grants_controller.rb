# A machine's sharing allowlist (when `sharing = list`): which projects, besides
# the owner, may pick up the box. Owner-managed; each add/remove is a recorded
# own-record act. machine-ownership.md.
class MachineGrantsController < ApplicationController
  before_action :set_machine

  def create
    project = Project.find(params[:project_id])
    grant = MachineGrant.new(machine: @machine, project: project)
    MachineGrant.transaction do
      grant.save!
      Event.record!(actor: Current.user.email_address, action: "shared machine",
                    machine: @machine, project: project,
                    summary: "Allowed #{project.name} on #{@machine.name}")
    end
    redirect_to @machine, notice: "Allowed #{project.name} on #{@machine.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @machine, alert: e.message.presence || "Couldn't share that machine."
  end

  def destroy
    grant = @machine.machine_grants.find(params[:id])
    project = grant.project
    MachineGrant.transaction do
      grant.destroy!
      Event.record!(actor: Current.user.email_address, action: "unshared machine",
                    machine: @machine, project: project,
                    summary: "Removed #{project.name} from #{@machine.name}")
    end
    redirect_to @machine, notice: "Removed #{project.name} from #{@machine.name}."
  end

  private

  def set_machine
    @machine = Machine.find(params[:machine_id])
  end
end
