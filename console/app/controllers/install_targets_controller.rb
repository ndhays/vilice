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
    # Looked up *within* the candidates, never by bare id: a box that is not one this
    # install may land on must be refused here as well as omitted from the picker.
    picked   = params[:machine_id].presence
    @machines = placeable_machines
    @machine  = @machines.find { |m| m.id.to_s == picked } if picked

    unless @machine
      flash.now[:alert] = picked ? "That box isn't one #{@install.name} can land on — it " \
                                   "may already be running it, or not be yours to use." \
                                 : "Pick a box to place #{@install.name} on."
      return render :new, status: :unprocessable_entity
    end

    if place_on(@machine)
      redirect_to new_machine_mutation_path(@machine, act: "deploy",
                                            install_id: @install.id, from: "install")
    else
      # The transaction rolled back, so the candidates are unchanged and already loaded.
      flash.now[:alert] = @install.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_install
    @install = Install.find(params[:install_id])
  end

  # Where this install could still go — the rule lives on the model, so this picker and
  # the readiness the install page reports can never disagree about what "free" means.
  # The per-machine name and hostname guards still have the last word at save time; this
  # list only keeps the obvious collisions out of the picker.
  def placeable_machines = @install.candidate_machines

  # The record is written before the deploy is even composed — the placement is itself a
  # control-plane act, and the deploy that follows is witnessed separately. The write
  # lives on the model so this door and the create form record it identically.
  def place_on(machine)
    Install.transaction { @install.place_on!(machine, actor: Current.user.email_address) }
    true
  rescue ActiveRecord::RecordInvalid => e
    @install.errors.add(:base, e.message) if @install.errors.empty?
    false
  end
end
