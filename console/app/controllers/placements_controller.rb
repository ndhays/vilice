# Place an existing app on one more box — the act that closes a placement gap.
#
# The gap itself is never closed on its own (decisions/drift-is-surfaced-never-closed.md):
# the console states *asked for 3 · serving 2* and offers this, a person presses it, and
# the deploy goes through the same witnessed ceremony as any other. Nothing here runs in
# the background, and nothing decides that a box should be added.
#
# Scaling down has no action here on purpose — that is `remove` on a target, a verb that
# already exists and is already witnessed. One way to take an app off a box, not two.
class PlacementsController < ApplicationController
  before_action :set_app

  def new
    @machines = placeable_machines
  end

  def create
    # Looked up *within* the candidates, never by bare id: a box that is not one this
    # app may land on must be refused here as well as omitted from the picker.
    picked   = params[:machine_id].presence
    @machines = placeable_machines
    @machine  = @machines.find { |m| m.id.to_s == picked } if picked

    unless @machine
      flash.now[:alert] = picked ? "That box isn't one #{@app.name} can land on — it " \
                                   "may already be running it, or not be yours to use." \
                                 : "Pick a box to place #{@app.name} on."
      return render :new, status: :unprocessable_entity
    end

    if place_on(@machine)
      redirect_to new_machine_mutation_path(@machine, act: "deploy",
                                            app_id: @app.id, from: "app")
    else
      # The transaction rolled back, so the candidates are unchanged and already loaded.
      flash.now[:alert] = @app.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_app
    @app = App.find(params[:app_id])
  end

  # Where this app could still go — the rule lives on the model, so this picker and
  # the readiness the app page reports can never disagree about what "free" means.
  # The per-machine name and hostname guards still have the last word at save time; this
  # list only keeps the obvious collisions out of the picker.
  def placeable_machines = @app.candidate_machines

  # The record is written before the deploy is even composed — the placement is itself a
  # control-plane act, and the deploy that follows is witnessed separately. The write
  # lives on the model so this door and the create form record it identically.
  def place_on(machine)
    App.transaction { @app.place_on!(machine, actor: Current.user.email_address) }
    true
  rescue ActiveRecord::RecordInvalid => e
    @app.errors.add(:base, e.message) if @app.errors.empty?
    false
  end
end
