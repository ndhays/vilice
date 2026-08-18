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
  # Installs this box fronts — the balancer role (decisions/one-primitive-composed.md).
  # Nullify, never destroy: turning a balancer off must not delete other people's
  # placements. They fall back to needing one, which surfaces as an install that can't
  # be routed rather than an install that vanished.
  has_many :fronted_installs, class_name: "Install", foreign_key: :balancer_id,
           inverse_of: :balancer, dependent: :nullify
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
  scope :shared,   -> { where.not(sharing: "dedicated") }
  scope :unowned,  -> { where(owner_id: nil) }
  # Boxes willing to front others. A balancer needs operate scope like any other box we
  # send a command to — `route` is an operate-scoped verb.
  scope :balancers, -> { where(balancer: true) }

  def balancer? = balancer

  # What this box carries, for the row's trailing glyph. Both use `size` rather than
  # `count`, so a preloaded list costs no extra query — the fleet list preloads them,
  # and a list that asks the database once per row is the thing this page must avoid.
  def app_count = installs.size

  # Hosts behind this balancer: the distinct boxes its fronted installs land on. A
  # balancer fronting nothing reports zero rather than nothing — "fronts 0 hosts" is
  # an answer, and a quiet blank would read as "not a balancer".
  def fronted_host_count
    fronted_installs.flat_map { |i| i.install_targets.map(&:machine_id) }.uniq.size
  end

  # The balancers this box sits behind. Read through the installs it runs, because
  # the relationship is *placement*, not machine-to-machine — the same edge the Fleet
  # grouping reads. A box can serve apps fronted by more than one, and a balancer
  # that fronts its own app is not behind itself. `size` over `count` again: the
  # fleet list preloads `installs: :balancer`, so this costs no query per row.
  #
  # It is a fact about this one box, which is why the row may carry it under *any*
  # grouping — unlike the fleet tree, which draws a relationship between rows and so
  # is only honest when the group is the fleet itself.
  def behind
    installs.filter_map(&:balancer).uniq.reject { |b| b == self }.sort_by(&:name)
  end

  # The table this box should be serving, derived from the installs that select it —
  # never hand-authored (decisions/one-primitive-composed.md). This is the *plan* half;
  # what the box reports fronting is the other. See RoutingTable.
  def routing_table = RoutingTable.for(self)

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

  # We have never had an answer from this box, which in practice means our key was never
  # authorized on it — the one thing the operator must do there by hand
  # (decisions/machine-onboarding.md). Distinct from `seen_unreachable?`, which is a box
  # we *did* reach and have since lost: that one has a different fix.
  def never_reached? = last_seen_at.nil?

  # We have heard from this box, so a call aimed at it can connect. Deliberately one
  # word for the *good* case and two distinct bad ones behind it, because they are
  # different problems with different fixes: `never_reached?` means our key was never
  # authorized there, `seen_unreachable?` means we had it and lost it.
  #
  # It is a reading of the last observe, never a claim — as fresh as that and no
  # fresher. Nothing here probes a box (blueprint/console/interface.md's honesty note).
  def reached? = !never_reached? && !seen_unreachable?

  # How this box reads in a picker. The authorize gap belongs on the option itself —
  # a name alone lets you choose a box that cannot yet be deployed to and find out
  # only when the SSH call fails.
  def machine_option_label = never_reached? ? "#{name} — not yet authorized" : name

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
