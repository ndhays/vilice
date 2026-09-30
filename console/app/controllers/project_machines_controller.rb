# The Project ↔ Machine edge. Attaching an existing fleet machine to a project is the
# M:N link the app flow draws from — the project's machine pool is the staging
# "queue". Creating a *brand-new* machine is machines#new; this is purely the join.
# The ProjectMachine join enforces Decision 1 (a dedicated box serves one project).
# The link is a recorded own-record act. (Detach is a planned follow-up.)
class ProjectMachinesController < ApplicationController
  before_action :set_project

  def create
    machine = Machine.find(params[:machine_id])
    link = ProjectMachine.new(project: @project, machine: machine)

    if record_link(link, machine)
      redirect_to @project, notice: "Added #{machine.name} to #{@project.name}."
    else
      redirect_to @project, alert: link.errors.full_messages.to_sentence.presence ||
        "Couldn't add that machine."
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  # Persist the link and record it atomically (record-before-act, Invariant 2).
  def record_link(link, machine)
    ProjectMachine.transaction do
      link.save!
      Event.record!(actor: Current.user.email_address, action: "added",
                    project: @project, machine: machine,
                    summary: "#{machine.name} to #{@project.name}")
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end
