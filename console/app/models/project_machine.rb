class ProjectMachine < ApplicationRecord
  belongs_to :project
  belongs_to :machine

  validates :machine_id, uniqueness: { scope: :project_id }
  validate :machine_permits_project

  private

  # The box must permit this project (decisions/machine-ownership.md): it owns
  # the box, or the box is shared with everyone, or the project is on its allowlist.
  # This is the guardrail that stops client 4 picking up client 3's box.
  def machine_permits_project
    return if machine.nil? || project.nil? || machine.permits?(project)

    errors.add(:machine, "isn't shared with #{project.name} — its owner must share it first")
  end
end
