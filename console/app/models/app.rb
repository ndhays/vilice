# An entry in the App Library — a saved, reusable app definition the admin curates
# (decisions/open/app-library.md). The catalog/bookmarking layer: what *can* be
# installed. The top of the three-tier model — App → Install → InstallTarget — and
# itself the head of its own release history (App → Version). Bookmarking, not
# security: the un-bypassable image allowlist is a separate Steward-side concern.
class App < ApplicationRecord
  include Searchable

  has_many :versions, dependent: :destroy
  # Exactly one version per app is the latest (DB-enforced partial unique index).
  has_one :latest_version, -> { where(latest: true) }, class_name: "Version"
  has_many :installs, dependent: :nullify
  has_many :labels, as: :labelable, dependent: :destroy

  # The name seeds the install name, which the box uses for its files, volumes, and
  # unit (`apps/<name>.json`). Steward rejects anything outside [A-Za-z0-9_-]
  # (auth.go `validClient`) and does not dash-case for you — so enforce it here,
  # box-safe end to end, rather than failing cryptically at deploy.
  NAME_FORMAT = /\A[A-Za-z0-9_-]+\z/
  # Env var / secret / secret-file names follow shell rules — the box uses them verbatim
  # (steward validEnvName). Validate here so a bad name fails in the library, not at deploy.
  ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  validates :name, presence: true, uniqueness: true,
                   format: { with: NAME_FORMAT, message: "may use letters, digits, dashes, and underscores" }

  # Port and health are the app's defaults, carried into the install form. Mirror
  # what the box enforces (steward validateState) so a bad value fails here — with a
  # clear message, before the act — not cryptically at deploy time. Both optional:
  # blank means "no app default", and the box falls back (port 8080, health "/").
  validates :port, numericality: { only_integer: true, greater_than_or_equal_to: 1024,
                                    less_than_or_equal_to: 65535 }, allow_nil: true
  # Health is a URL path Caddy probes — it must start with "/".
  validates :health, format: { with: %r{\A/}, message: "must start with /" }, allow_blank: true

  # The app's declared inputs — *names only*, no values (values are supplied at install).
  #   env          : [{ "key" => "PASSWORD", "secret" => true }, …]  — secret? = off-record.
  #   secret_files : [{ "name" => "config", "path" => "/etc/zot/config.json" }, …] — mounted.
  # "secrets are env vars": a secret is just an env entry delivered off-record (the box
  # mirrors this — env vs Secret=type=env). Files are separate because they're mounted.
  validate :env_well_formed
  validate :secret_files_well_formed

  # env / secret_files default to [] (DB default), but guard against a stray nil.
  def env = self[:env] || []
  def secret_files = self[:secret_files] || []

  # The env var names this app declares (both plain and secret).
  def env_keys = env.filter_map { |e| e["key"] }
  # The names whose values must be supplied off-record (secret env vars + every file).
  def secret_keys = env.select { |e| e["secret"] }.filter_map { |e| e["key"] }

  # Promote one version to latest; clears the others in the same transaction.
  def set_latest!(version)
    transaction do
      versions.where.not(id: version.id).update_all(latest: false)
      version.update!(latest: true)
    end
  end

  # `search` (name + label selectors) comes from the Searchable concern.

  private

  def env_well_formed
    return errors.add(:env, "must be a list") unless env.is_a?(Array)

    seen = []
    env.each do |e|
      unless e.is_a?(Hash) && e["key"].is_a?(String)
        return errors.add(:env, "each entry needs a key")
      end
      key = e["key"]
      errors.add(:env, "#{key.inspect} is not a valid env name") unless key.match?(ENV_NAME)
      errors.add(:env, "#{key} is listed twice") if seen.include?(key)
      seen << key
    end
  end

  def secret_files_well_formed
    return errors.add(:secret_files, "must be a list") unless secret_files.is_a?(Array)

    seen = []
    secret_files.each do |f|
      unless f.is_a?(Hash) && f["name"].is_a?(String) && f["path"].is_a?(String)
        return errors.add(:secret_files, "each file needs a name and a path")
      end
      errors.add(:secret_files, "#{f["name"].inspect} is not a valid name") unless f["name"].match?(ENV_NAME)
      errors.add(:secret_files, "#{f["name"]} path must be absolute (start with /)") unless f["path"].start_with?("/")
      errors.add(:secret_files, "#{f["name"]} is listed twice") if seen.include?(f["name"])
      seen << f["name"]
    end
    # A name can't be both an env var and a file — mirrors the box (steward validateState).
    (seen & env_keys).each { |n| errors.add(:secret_files, "#{n} is both an env var and a file") }
  end
end
