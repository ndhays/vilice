class Install < ApplicationRecord
  # Tenancy is the outermost, optional ring — an install is a placement, and a placement
  # is coherent with no client anywhere (decisions/console-layers.md). A Project, when
  # there is one, is context: whose work it is, never what contains it.
  belongs_to :project, optional: true
  # The App Library entry this was installed from; nil = a custom image (slice 2b).
  belongs_to :app_template, optional: true
  # The release deployed; nil for custom images. `image` is copied from it at install.
  belongs_to :version, optional: true

  has_many :install_targets, dependent: :destroy
  has_many :machines, through: :install_targets
  has_many :events, dependent: :nullify

  # This name is the one the box actually uses — `apps/<name>.json`, volumes, the unit.
  # Steward rejects anything outside [A-Za-z0-9_-] (auth.go `validClient`) and won't
  # dash-case it, so validate here (matching AppTemplate's rule) to fail before the act. Port
  # and health are deployed verbatim too, so they mirror the box's bounds like AppTemplate's.
  NAME_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/

  # No uniqueness here on purpose. The name has to be free *on the box* — that's the
  # namespace it lands in — and `InstallTarget#install_name_free_on_machine` already
  # enforces exactly that, independent of any project. Scoping it per project instead
  # would both miss the collision that matters and require a project to exist.
  validates :name, presence: true,
                   format: { with: NAME_FORMAT, message: "must start with a letter or digit, then letters, digits, dashes, and underscores" }
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

  # A host path is confined to /srv, mirroring the box's `bindRoots`. This is not a
  # tidiness rule: a bind mount of host root hands an operate key ~steward/.ssh, and with
  # it a grant — the box's own `TestBindMountsAreConfinedToTheDataRoot` calls it "the
  # escalation that was live". The box refuses it either way; refusing it here means you
  # find out where you typed it rather than at the far end, after building on it.
  BIND_ROOT = "/srv".freeze

  # One rule, shared: an Install's own volumes and an AppTemplate's accessory volumes are the
  # same declaration going to the same place. Returns a sentence or nil.
  def self.volume_error(v)
    v = v.to_s
    return "#{v.inspect} must look like storage:/path/in/container" unless v.match?(VOLUME_FORMAT)

    source = v.split(":", 2).first.to_s
    return nil unless source.start_with?("/")

    clean = Pathname.new(source).cleanpath.to_s
    return nil if clean == BIND_ROOT || clean.start_with?("#{BIND_ROOT}/")

    "bind mount #{source.inspect} is outside #{BIND_ROOT} — put app data under " \
      "#{BIND_ROOT}, or use a named volume"
  end

  validate :volumes_well_formed

  # Named volumes that survive every redeploy — the declaration, not the data. Stored in
  # the `config` blob alongside env (deploy-config-model.md: a volume is a *ref* to data).
  def volumes = Array(config["volumes"])

  # The release command this install deploys with — copied from the App at create, so a
  # later library edit never silently changes what an already-placed app runs on its next
  # deploy. argv, so it reaches the box as a list and never as a shell string.
  def release = Array(config["release"])

  # ── Secret values ──────────────────────────────────────────────────────────
  # The values behind the names the App declares. **Encrypted at rest**, the same
  # protection a Machine's private key gets, and **resent on every deploy** so a deploy
  # is self-contained — no set-once ordering, no dangling secret waiting for an app
  # (decisions/declarative-deploy.md).
  #
  # They ride the envelope on **stdin**, never argv, so they are never recorded: the
  # chain commits to the spec digest, which covers secret *names* and never their values.
  # Nothing here is ever rendered back to a page — a value goes in, and only ever comes
  # out on its way to a box.
  serialize :secret_values, coder: JSON
  encrypts :secret_values

  def secret_values = self[:secret_values] || {}

  # The containers this install brings with it — a database, a cache — copied from the
  # App at create like the release command, and for the same reason: a later library
  # edit must not silently change what an already-placed app runs.
  def accessories = Array(config["accessories"])

  # The app's other containers — a worker, a clock — copied from the App at create like
  # everything else here. They deploy and roll back with the app, so a worker can never
  # end up running different code from the web process.
  def processes = Array(config["processes"])

  # An accessory keeps data on *that box's* disk, exactly like a volume, so an install
  # that brings one is single-placement for the same reason. Folded into `replicable?`
  # rather than bolted beside it, because it is the same fact: a thing that keeps data
  # cannot be multiplied.
  def stateful_accessories? = accessories.any? { |a| Array(a["volumes"]).any? }

  # ── The intention, and the gap ─────────────────────────────────────────────
  # Replication is stateless-only (one-primitive-composed.md). A volume is data on *that
  # box's* disk, so N replicas would be N diverging datasets — a stateful app is
  # single-placement, full stop. Derived from the volumes it declares rather than a flag:
  # a flag is a promise about the spec, and this is the spec.
  def replicable? = volumes.empty? && !stateful_accessories?

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

  def short? = placement_gap.negative?

  # ── Whether the gap can be closed right now ────────────────────────────────
  # "Asked for 3 · serving 2" says there is a gap. It does not say whether you can do
  # anything about it, and those want different answers: one is a click, the other is
  # *go get a box*. Both are surfaced; neither is acted on
  # (decisions/drift-is-surfaced-never-closed.md).
  #
  # Boxes this install could still be placed on: operate-scoped (an observe key cannot
  # deploy), within the project when there is one, and not already carrying it. One
  # definition, because the picker, the page that offers the act, and Status all ask
  # it — and three copies would drift, the way `added` and `placed` did.
  #
  # Pass a preloaded `pool` to answer for many installs without a query each; a list
  # must not ask the database once per row. **Two** preloads are needed for that to
  # hold — the pool must carry `project_machines`, and the installs must carry their
  # `install_targets` — and `install_test.rb` pins it, because half of it is silent.
  def candidate_machines(pool = nil)
    pool ||= Machine.operate.includes(:project_machines).order(:name)
    taken = live_targets.map(&:machine_id)
    pool.select do |m|
      m.operate? && !taken.include?(m.id) &&
        (project_id.nil? || m.project_machines.any? { |pm| pm.project_id == project_id })
    end
  end

  # Candidates we have actually heard from. Placing is a control-plane act and works on
  # any candidate — the target sits `pending` and reaches nothing — but the deploy that
  # follows cannot connect to a box that never authorized us. So **ready** means ready
  # to *finish*, not merely ready to record.
  def ready_machines(pool = nil) = candidate_machines(pool).select(&:reached?)

  def ready_to_place?(pool = nil) = short? && ready_machines(pool).any?

  # Land this install on one more box: the target, plus the `placed install` act that
  # accounts for it. **Both doors into a placement go through here** — creating an
  # install with a box already chosen, and closing a gap later from the install's own
  # page — because the same thing recorded two different ways is the drift this layer
  # exists to prevent. It was recorded as `added` from one door and `placed` from the
  # other until this method existed.
  #
  # Reaches no box: the target is `pending` and the gap does not move. It narrows only
  # when observe reports the app running (drift-is-surfaced-never-closed.md). Raises —
  # the caller owns the transaction and decides what a failure looks like.
  def place_on!(machine, actor:)
    install_targets.create!(machine: machine, status: "pending")
    Event.record!(actor: actor, action: "placed", project: project, install: self,
                  machine: machine, summary: "#{name} on #{machine.name}")
  end

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
    where(id: joins("LEFT JOIN app_templates ON app_templates.id = installs.app_template_id")
              .where("installs.name LIKE :q OR installs.hostname LIKE :q OR app_templates.name LIKE :q", q: like)
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
    app[:release] = release if release.any?
    # Copied through as-is: the console's stored shape is the box's spec shape, so this
    # is a hand-off rather than a translation, and there is no second definition to drift.
    app[:accessories] = accessories if accessories.any?
    app[:processes]   = processes if processes.any?
    app[:secrets]      = secret_env_names if secret_env_names.any?
    app[:secret_files] = secret_file_paths if secret_file_paths.any?

    # Values in the *other half* of the envelope — bound to the spec, never part of it,
    # and never recorded. Only names this spec actually declares are sent: a value left
    # over from a name the library has since dropped is not something to hand a box.
    envelope = { app: app.compact }
    envelope[:secret_values] = secret_values.slice(*declared_secret_names) if declared_secret_names.any?
    envelope
  end

  # ── What the box will ask for ───────────────────────────────────────────────
  # Declared on the App (and on its accessories), never here: the library carries the
  # shape, the install carries the values. One reading of that shape, used by the form,
  # by the envelope, and by the check that runs before the ceremony.

  def secret_env_names = app_template ? app_template.secret_keys : []

  # Secret files, as the box wants them: `{ name => container path }`.
  def secret_file_paths
    return {} unless app_template

    app_template.secret_files.to_h { |f| [ f["name"], f["path"] ] }
  end

  # Plain env var names — recorded in the clear, so their values are part of the spec
  # rather than of the values half.
  def plain_env_names = app_template ? app_template.env_recorded : []

  # Every name that needs a value, an accessory's included: a database password is the
  # install's to supply even though the database is the thing that reads it.
  def declared_secret_names
    return [] unless app_template

    (secret_env_names + secret_file_paths.keys +
      accessories.flat_map { |a| Array(a["secrets"]) }).uniq
  end

  # Declared, and we hold nothing for it. The box refuses a deploy carrying one of these,
  # so the console says so first rather than letting the ceremony fail at the far end.
  def missing_secrets = declared_secret_names.reject { |n| secret_values[n].to_s.present? }

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
    volumes.each do |v|
      next unless (message = Install.volume_error(v))

      return errors.add(:base, "Volume #{message}.")
    end
  end
end
