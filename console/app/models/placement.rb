class Placement < ApplicationRecord
  belongs_to :app
  belongs_to :machine

  enum :strategy, { single: "single", replica: "replica" }, default: "single", prefix: true

  # Where this placement stands. desired_image is what we asked Vilice to run;
  # current_image is what it reports running.
  enum :status,
       { pending: "pending", deploying: "deploying", running: "running",
         failed: "failed", retired: "retired" },
       default: "pending"

  validates :machine_id, uniqueness: { scope: :app_id }

  # Isolation (decisions/open/install-journeys.md #4) — apps share a box's namespace:
  # one `apps/<name>.json`, one Caddy edge, named volumes. So an app's name and
  # hostname must be unique *per machine*, not just per project — a collision on a
  # shared box would let one Project clobber another's app or hijack its route.
  # Enforced here, at the App×Machine join, so it holds whatever the entry point
  # (the box is the trust boundary; this is the control-plane guardrail above it).
  validate :app_name_free_on_machine
  validate :hostname_free_on_machine

  # In step when the running image matches what we asked for.
  def in_sync?
    running? && current_image.present? && current_image == desired_image
  end

  # Where this one placement stands, in the same words `App#state` uses — that
  # ladder is now literally "the worst of these". The app page used to badge a
  # target with its raw `status`, which knows nothing about the box being unreachable
  # or the image having drifted, so a row could read `running` under a header that
  # said `unreachable`.
  def state
    return "failed"      if failed?
    return "unreachable" if running? && machine.seen_unreachable?
    return "drift"       if running? && current_image.present? && !in_sync?
    return "deploying"   if deploying?
    return "pending"     if pending?
    "running"
  end

  # An act travels scoped SSH to this box. If we cannot reach it, every verb is
  # certain to fail — so none is offered (blueprint/console/interface.md).
  def actionable? = machine.operate? && !machine.seen_unreachable?

  private

  # Other live targets on this same box. A retired target frees its name.
  def peers_on_machine
    return Placement.none if machine_id.nil?

    scope = Placement.where(machine_id: machine_id).where.not(status: "retired")
    scope = scope.where.not(app_id: app.id) if app&.id
    scope = scope.where.not(id: id) if persisted?
    scope
  end

  def app_name_free_on_machine
    return if app.nil? || app.name.blank?
    return unless peers_on_machine.joins(:app).where(apps: { name: app.name }).exists?

    errors.add(:base, %(An app named "#{app.name}" is already on #{machine&.name} — names are unique per machine.))
  end

  def hostname_free_on_machine
    return if app.nil? || app.hostname.blank?
    return unless peers_on_machine.joins(:app).where(apps: { hostname: app.hostname }).exists?

    errors.add(:base, "Hostname #{app.hostname} is already served on #{machine&.name} — hostnames are unique per machine.")
  end
end
