# Adding and removing labels — a control-plane act with no box involved, so it
# lands only in Vilice Console's *own* record (decisions/two-records.md), attributed
# to the signed-in human. The Event and the change are written together in one
# transaction: no recorded act without the change, no change off the record.
class LabelsController < ApplicationController
  def create
    labelable = find_labelable
    label = labelable.labels.new(label_params)

    if record(action: "added", label: label, on: labelable) { label.save }
      redirect_back fallback_location: labelable, notice: "Added label #{label} (recorded)."
    else
      redirect_back fallback_location: labelable, alert: label.errors.full_messages.to_sentence
    end
  end

  def destroy
    label = Label.find(params[:id])
    labelable = label.labelable
    record(action: "removed", label: label, on: labelable) { label.destroy! }
    redirect_back fallback_location: labelable, notice: "Removed label #{label} (recorded)."
  end

  private

  def find_labelable
    if params[:machine_id] then Machine.find(params[:machine_id])
    elsif params[:project_id] then Project.find(params[:project_id])
    elsif params[:app_template_id] then AppTemplate.find(params[:app_template_id])
    else raise ActiveRecord::RecordNotFound
    end
  end

  def label_params
    params.require(:label).permit(:key, :value)
  end

  # Run the change and record it together, attributed to the human. The act is
  # only recorded if the change commits — for a local domain mutation, atomic is
  # the right shape of "before it runs" (box commands keep the stricter ordering).
  def record(action:, label:, on:)
    ok = false
    ActiveRecord::Base.transaction do
      ok = yield
      raise ActiveRecord::Rollback unless ok
      preposition = action.start_with?("removed") ? "from" : "on"
      Event.record!(
        actor: Current.user.email_address, action: action,
        machine: on.is_a?(Machine) ? on : nil,
        project: on.is_a?(Project) ? on : nil,
        summary: "#{label} #{preposition} #{on.name}",
        raw: { key: label.key, value: label.value }
      )
    end
    ok
  end
end
