class Install < ApplicationRecord
  # Tenancy is the outermost, optional ring — an install is a placement, and a placement
  # is coherent with no client anywhere (decisions/console-layers.md). A Project, when
  # there is one, is context: whose work it is, never what contains it.
  belongs_to :project, optional: true
  # The App Library entry this was installed from; nil = a custom image (slice 2b).
  belongs_to :app, optional: true
  # The release deployed; nil for custom images. `image` is copied from it at install.
  belongs_to :version, optional: true

  has_many :install_targets, dependent: :destroy
  has_many :machines, through: :install_targets
  has_many :events, dependent: :nullify

  # This name is the one the box actually uses — `apps/<name>.json`, volumes, the unit.
  # Steward rejects anything outside [A-Za-z0-9_-] (auth.go `validClient`) and won't
  # dash-case it, so validate here (matching App's rule) to fail before the act. Port
  # and health are deployed verbatim too, so they mirror the box's bounds like App's.
  NAME_FORMAT = /\A[A-Za-z0-9_-]+\z/

  # No uniqueness here on purpose. The name has to be free *on the box* — that's the
  # namespace it lands in — and `InstallTarget#install_name_free_on_machine` already
  # enforces exactly that, independent of any project. Scoping it per project instead
  # would both miss the collision that matters and require a project to exist.
  validates :name, presence: true,
                   format: { with: NAME_FORMAT, message: "may use letters, digits, dashes, and underscores" }
  validates :port, numericality: { only_integer: true, greater_than_or_equal_to: 1024,
                                   less_than_or_equal_to: 65535 }, allow_nil: true
  validates :health, format: { with: %r{\A/}, message: "must start with /" }, allow_blank: true

  # How the app is reached, which is what decides whether a count above 1 can mean
  # anything (decisions/one-primitive-composed.md). On the edge, DNS points at the box and
  # the box terminates its own TLS — one box, one IP. Behind a balancer, the box is a
  # backend and DNS points at the balancer, so more boxes are just more upstreams.
  enum :exposure, { edge: "edge", balanced: "balanced" }, default: "edge", prefix: :exposure

  # Which box fronts this install. Only meaningful when balanced — on the edge the app is
  # reached at its own box and there is nothing in front of it. A Balancer is a Machine in
  # a role, not a separate primitive (decisions/one-primitive-composed.md).
  belongs_to :balancer, class_name: "Machine", optional: true
  validate :balancer_fits_exposure

  # How many boxes should serve this. The **intention** — a claim about what was asked
  # for, never a reading of what is (decisions/drift-is-surfaced-never-closed.md).
  # Nothing reconciles it: the gap it opens against reality is closed by a named act or
  # it stays open.
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :count_within_replication_limit
  validate :count_within_exposure_limit

  # A volume is `<source>:<container-path>[:opts]` — a named volume (`storage`) or a host
  # path (`/srv/x`), then an absolute mount path. Mirrors the box's `Volume=` line
  # (steward/quadlet.go) and backup's `volumeSource` split, so a malformed mount fails here,
  # before the act, like name/port/health above.
  VOLUME_FORMAT = %r{\A([A-Za-z0-9_.-]+|/[^:\s]+):/[^:\s]+(:[A-Za-z,]+)?\z}

  validate :volumes_well_formed

  # Named volumes that survive every redeploy — the declaration, not the data. Stored in
  # the `config` blob alongside env (deploy-config-model.md: a volume is a *ref* to data).
  def volumes = Array(config["volumes"])

  # ── The intention, and the gap ─────────────────────────────────────────────
  # Replication is stateless-only (one-primitive-composed.md). A volume is data on *that
  # box's* disk, so N replicas would be N diverging datasets — a stateful app is
  # single-placement, full stop. Derived from the volumes it declares rather than a flag:
  # a flag is a promise about the spec, and this is the spec.
  def replicable? = volumes.empty?

  # Where it was actually placed. A retired target is gone, not a placement at zero.
  def live_targets = install_targets.reject(&:install_retired?)

  # **Reality** — boxes the app is genuinely serving from, per what the box reported
  # (InstallTarget#status is observe-reconciled, not written by the deploy). An install
  # running on a box we can no longer reach is not counted as serving.
  def serving_count
    live_targets.count { |t| t.install_running? && !t.machine.seen_unreachable? }
  end

  # The gap, signed: negative is short of the intention, positive is more than was asked
  # for. Zero is in step. Deliberately not folded into `state` — an intention is not a
  # state, and the UI has to keep them visibly apart.
  def placement_gap = serving_count - count

  def in_step? = placement_gap.zero?

  # The rolled-up state of this placement — worst-but-actionable wins across live
  # targets, in the order below. One word, shared by the row's leading glyph, the
  # Status page's exception list, and the Installs list's grouping, so all three
  # agree by construction rather than by three copies of the same ladder.
  #
  # HONESTY NOTE: built from *stored* state (the last deploy outcome, last-seen
  # reachability, recorded image drift), never a fresh probe. Until persistent
  # ingestion lands (#6 in decisions/open/ui-roadmap.md), "running" means "last we
  # knew". The precise word rides the row's tooltip; nothing here may overclaim
  # truth we don't have.
  #
  # `placement_gap` is deliberately *not* folded in: an intention is not a state
  # (decisions/drift-is-surfaced-never-closed.md), and the UI keeps them apart.
  STATES = %w[failed unreachable drift deploying pending running unplaced].freeze

  # The states that need a person. Transient states (deploying/pending) and healthy
  # ones stay quiet — they resolve on their own or are already fine. Read by the
  # Status page's exception list and by the Installs headline, so "needs a look"
  # means one thing in both places.
  EXCEPTION_STATES = %w[failed unreachable drift].freeze

  def needs_a_look? = EXCEPTION_STATES.include?(state)

  # The worst state among the live placements — one ladder, defined once on the
  # target and folded here, so a target row and the install header can never disagree.
  def state
    states = live_targets.map(&:state)
    return "unplaced" if states.empty?
    STATES.find { |s| states.include?(s) } || "running"
  end

  # Free-text list search over what identifies a placement: its own name, the
  # hostname it serves, the app it came from, and the box it runs on. No selector
  # grammar here — installs carry no labels, and the categorical axes (project, app,
  # exposure, edge, state) are the *grouping*, so a selector would be a second way
  # to ask a question the chips already answer. See decisions/open/list-search.md.
  def self.search(query)
    query = query.to_s.strip
    return all if query.blank?

    like = "%#{query}%"
    where(id: joins("LEFT JOIN apps ON apps.id = installs.app_id")
              .where("installs.name LIKE :q OR installs.hostname LIKE :q OR apps.name LIKE :q", q: like)
              .select(:id))
      .or(where(id: joins(install_targets: :machine).where("machines.name LIKE ?", like).select(:id)))
  end

  # The desired-state envelope Steward's `deploy` reads on stdin
  # (steward/deploy.go `deployEnvelope`/`appSpec`). The Install *is* the spec; a
  # deploy just pins a new `image` digest, with hostname/port/health overridable
  # from the compose form. Secret *values* never live here — that's #14's
  # off-record channel — so `secret_values` is omitted.
  def deploy_envelope(image:, hostname: self.hostname, port: self.port, health: self.health)
    app = { image: image, hostnames: Array(hostname).reject(&:blank?),
            port: port.presence, health: health.presence }
    app[:env]     = config["env"] if config["env"].present?
    app[:volumes] = volumes if volumes.any?
    { app: app.compact }
  end

  private

  # A balancer only makes sense in front of something balanced, and only a box that has
  # taken the role can be one. Both are refused rather than quietly ignored — an install
  # pointing at a box that isn't fronting anything would look routed and not be.
  def balancer_fits_exposure
    return if balancer.nil?

    errors.add(:balancer, "only applies behind a balancer — this install is on the edge") if exposure_edge?
    errors.add(:balancer, "#{balancer.name} isn't marked as a balancer") unless balancer.balancer?
  end

  # The exposure gate. An install on the edge is reached at its own address, so a second
  # box cannot serve the same hostname — asking for one is stating something no amount of
  # deploying will deliver. Refused here rather than allowed and left to disappoint.
  def count_within_exposure_limit
    return unless exposure_edge? && count.to_i > 1

    errors.add(:count, "must be 1 on the edge — DNS points at one box. " \
                       "Put it behind a balancer to run more than one.")
  end

  # The stateless-only gate, enforced rather than merely offered in the form: a spec that
  # declares a volume may not also ask for more than one box.
  def count_within_replication_limit
    return if replicable? || count.to_i <= 1

    errors.add(:count, "must be 1 — #{name.presence || 'this app'} declares a volume, " \
                       "and replicas would each keep their own copy of that data.")
  end

  def volumes_well_formed
    bad = volumes.reject { |v| v.to_s.match?(VOLUME_FORMAT) }
    return if bad.empty?

    errors.add(:base, "Volume #{bad.first.inspect} must look like storage:/path/in/container.")
  end
end
