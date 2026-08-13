class InstallTarget < ApplicationRecord
  belongs_to :install
  belongs_to :machine

  enum :strategy, { single: "single", replica: "replica" }, default: "single", prefix: true

  # Where this target stands. desired_image is what we asked Steward to run;
  # current_image is what it reports running.
  enum :status,
       { pending: "pending", deploying: "deploying", running: "running",
         failed: "failed", retired: "retired" },
       default: "pending", prefix: :install

  validates :machine_id, uniqueness: { scope: :install_id }

  # Isolation (decisions/open/install-journeys.md #4) — apps share a box's namespace:
  # one `apps/<name>.json`, one Caddy edge, named volumes. So an install's name and
  # hostname must be unique *per machine*, not just per project — a collision on a
  # shared box would let one Project clobber another's app or hijack its route.
  # Enforced here, at the Install×Machine join, so it holds whatever the entry point
  # (the box is the trust boundary; this is the control-plane guardrail above it).
  validate :install_name_free_on_machine
  validate :hostname_free_on_machine

  # In step when the running image matches what we asked for.
  def in_sync?
    install_running? && current_image.present? && current_image == desired_image
  end

  # Where this one placement stands, in the same words `Install#state` uses — that
  # ladder is now literally "the worst of these". The install page used to badge a
  # target with its raw `status`, which knows nothing about the box being unreachable
  # or the image having drifted, so a row could read `running` under a header that
  # said `unreachable`.
  def state
    return "failed"      if install_failed?
    return "unreachable" if install_running? && machine.seen_unreachable?
    return "drift"       if install_running? && current_image.present? && !in_sync?
    return "deploying"   if install_deploying?
    return "pending"     if install_pending?
    "running"
  end

  # An act travels scoped SSH to this box. If we cannot reach it, every verb is
  # certain to fail — so none is offered (blueprint/console/interface.md).
  def actionable? = machine.operate? && !machine.seen_unreachable?

  private

  # Other live targets on this same box. A retired target frees its name.
  def peers_on_machine
    return InstallTarget.none if machine_id.nil?

    scope = InstallTarget.where(machine_id: machine_id).where.not(status: "retired")
    scope = scope.where.not(install_id: install.id) if install&.id
    scope = scope.where.not(id: id) if persisted?
    scope
  end

  def install_name_free_on_machine
    return if install.nil? || install.name.blank?
    return unless peers_on_machine.joins(:install).where(installs: { name: install.name }).exists?

    errors.add(:base, %(An install named "#{install.name}" is already on #{machine&.name} — names are unique per machine.))
  end

  def hostname_free_on_machine
    return if install.nil? || install.hostname.blank?
    return unless peers_on_machine.joins(:install).where(installs: { hostname: install.hostname }).exists?

    errors.add(:base, "Hostname #{install.hostname} is already served on #{machine&.name} — hostnames are unique per machine.")
  end
end
