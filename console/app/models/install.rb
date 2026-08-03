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

  # A volume is `<source>:<container-path>[:opts]` — a named volume (`storage`) or a host
  # path (`/srv/x`), then an absolute mount path. Mirrors the box's `Volume=` line
  # (steward/quadlet.go) and backup's `volumeSource` split, so a malformed mount fails here,
  # before the act, like name/port/health above.
  VOLUME_FORMAT = %r{\A([A-Za-z0-9_.-]+|/[^:\s]+):/[^:\s]+(:[A-Za-z,]+)?\z}

  validate :volumes_well_formed

  # Named volumes that survive every redeploy — the declaration, not the data. Stored in
  # the `config` blob alongside env (deploy-config-model.md: a volume is a *ref* to data).
  def volumes = Array(config["volumes"])

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

  def volumes_well_formed
    bad = volumes.reject { |v| v.to_s.match?(VOLUME_FORMAT) }
    return if bad.empty?

    errors.add(:base, "Volume #{bad.first.inspect} must look like storage:/path/in/container.")
  end
end
