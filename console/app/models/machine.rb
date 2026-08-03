class Machine < ApplicationRecord
  # Name + label search, shared with App/Project (decisions/open/list-search.md).
  include Searchable

  # Decision 2 — the SSH private key is encrypted at rest. The public half is
  # `steward authorize`d on the box; revoking one machine never touches another.
  encrypts :ssh_private_key

  # The scope this machine's key carries on the box. observe ⊂ operate ⊂ grant.
  # `grant` mints and revokes keys and nothing else — it is not a shell, so holding one
  # is not holding the box (decisions/no-key-gets-a-shell.md). Steward Console defaults to
  # observe and is never root.
  enum :scope, { observe: "observe", operate: "operate", grant: "grant" }, default: "observe"

  # Reachability, as last read from Steward's record.
  enum :status, { unknown: "unknown", reachable: "reachable", unreachable: "unreachable" },
       default: "unknown", prefix: :seen

  # Who owns the box (the client whose hardware it is). Nullable — a released or
  # unclaimed box is unowned. Deleting an owning project is blocked, not nullified
  # (decisions/machine-ownership.md), so we never orphan an owner silently.
  belongs_to :owner, class_name: "Project", optional: true

  has_many :project_machines, dependent: :destroy
  has_many :projects, through: :project_machines
  has_many :machine_grants, dependent: :destroy
  has_many :granted_projects, through: :machine_grants, source: :project
  has_many :install_targets, dependent: :destroy
  has_many :installs, through: :install_targets
  has_many :snapshots, dependent: :destroy
  has_many :events, dependent: :nullify
  has_many :labels, as: :labelable, dependent: :destroy

  # How the box is shared. Explicit and never wide-open by accident: a fresh box
  # is `dedicated` (owner only). `everyone` = open multi-tenant; `list` = owner
  # plus the projects in `machine_grants`. Replaces the old `multi_tenant` boolean.
  enum :sharing, { dedicated: "dedicated", everyone: "everyone", list: "list" },
       default: "dedicated", prefix: :sharing

  validates :name, presence: true, uniqueness: true
  validates :ssh_host, presence: true
  validates :ssh_user, presence: true
  validates :ssh_port, numericality: { only_integer: true, in: 1..65_535 }

  # Shared in any form — anything but dedicated (for counts and badges).
  scope :shared,  -> { where.not(sharing: "dedicated") }
  scope :unowned, -> { where(owner_id: nil) }

  def unowned? = owner_id.nil?

  # May this Project attach to / use this box? The single guardrail behind the
  # attach query and the ProjectMachine join. Owner always may; `everyone` lets
  # anyone; `list` lets the allow-listed projects. An unowned dedicated box
  # permits no one — it's inert until re-owned or shared (surfaced on the fleet
  # page so it isn't lost).
  def permits?(project)
    return false if project.nil?
    owner_id == project.id || sharing_everyone? ||
      (sharing_list? && granted_projects.exists?(project.id))
  end

  # The line to run on the box to let Steward Console in — authorizes our public key as a
  # named client at this machine's scope (decisions/open/machine-onboarding.md).
  # Steward Console's key is born at observe/operate scope; never root.
  def authorize_command
    return if ssh_public_key.blank?

    client = ENV.fetch("STEWARD_CLIENT_NAME", "console")
    %(steward authorize "#{ssh_public_key}" --client #{client} --scope #{scope})
  end

  # The line to run on the box to cut Steward Console's access — the counterpart to
  # authorize_command. Removing the Machine here doesn't run this (the box keeps its
  # authorized key until the operator revokes it on the box itself).
  def revoke_command
    "steward revoke #{ENV.fetch('STEWARD_CLIENT_NAME', 'console')}"
  end
end
