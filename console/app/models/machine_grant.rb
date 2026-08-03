# One entry in a machine's sharing allowlist: a Project the box will accept when
# `sharing = list` (decisions/machine-ownership.md). The owner manages these.
# Deleting the granted Project removes its grant (dependent: :destroy from Project);
# the owner's box is untouched.
class MachineGrant < ApplicationRecord
  belongs_to :machine
  belongs_to :project

  validates :project_id, uniqueness: { scope: :machine_id }
end
