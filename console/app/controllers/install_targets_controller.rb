# Place an existing install on one more box — the act that closes a placement gap.
#
# The gap itself is never closed on its own (decisions/drift-is-surfaced-never-closed.md):
# the console states *asked for 3 · serving 2* and offers this, a person presses it, and
# the deploy goes through the same witnessed ceremony as any other. Nothing here runs in
# the background, and nothing decides that a box should be added.
#
# Scaling down has no action here on purpose — that is `remove` on a target, a verb that
# already exists and is already witnessed. One way to take an app off a box, not two.
class InstallTargetsController < ApplicationController
  before_action :set_install

  def new
    @machines = placeable_machines
  end

  def create
    @machine = placeable_machines.find_by(id: params[:machine_id])

    unless @machine
      @machines = placeable_machines
      flash.now[:alert] = "Pick a box to place #{@install.name} on."
      return render :new, status: :unprocessable_entity
    end

    if place_on(@machine)
      redirect_to new_machine_mutation_path(@machine, act: "deploy",
                                            install_id: @install.id, from: "install")
    else
      @machines = placeable_machines
      flash.now[:alert] = @install.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_install
    @install = Install.find(params[:install_id])
  end

  # Boxes this install could still go on: operate-scoped (an observe key can't deploy),
  # within the project when there is one, and not already carrying it. The per-machine
  # name and hostname guards still have the last word at save time — this list only
  # keeps the obvious collisions out of the picker.
  def placeable_machines
    scope = (@install.project&.machines || Machine.all).operate
    scope.where.not(id: @install.live_targets.map(&:machine_id)).order(:name)
  end

  # The record is written here, before the deploy is even composed — the placement is
  # itself a control-plane act, and the deploy that follows is witnessed separately.
  def place_on(machine)
    Install.transaction do
      @install.install_targets.create!(machine: machine, status: "pending")
      Event.record!(
        actor: Current.user.email_address, action: "placed",
        project: @install.project, install: @install, machine: machine,
        summary: "#{@install.name} on #{machine.name}"
      )
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    @install.errors.add(:base, e.message) if @install.errors.empty?
    false
  end
end
