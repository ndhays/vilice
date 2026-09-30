# An entry in the App Library — a saved, reusable app definition the admin curates
# (decisions/open/app-library.md). The catalog/bookmarking layer: what *can* be
# installed. The top of the three-tier model — AppTemplate → App → Placement — and
# itself the head of its own release history (AppTemplate → Version). Bookmarking, not
# security: the un-bypassable image allowlist is a separate Steward-side concern.
class AppTemplate < ApplicationRecord
  include Searchable

  has_many :versions, dependent: :destroy
  # Exactly one version per app is the latest (DB-enforced partial unique index).
  has_one :latest_version, -> { where(latest: true) }, class_name: "Version"
  has_many :apps, dependent: :nullify
  has_many :labels, as: :labelable, dependent: :destroy

  # The name seeds the app name, which the box uses for its files, volumes, and
  # unit (`apps/<name>.json`). Steward rejects anything outside [A-Za-z0-9_-], and
  # refuses a leading dash besides — a name is handed to systemctl and podman as an
  # argument, and one starting with a dash reads as a flag. It does not dash-case for
  # you either, so enforce both here, box-safe end to end, rather than failing
  # cryptically at deploy.
  NAME_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
  # Env var / secret / secret-file names follow shell rules — the box uses them verbatim
  # (steward validEnvName). Validate here so a bad name fails in the library, not at deploy.
  ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  validates :name, presence: true, uniqueness: true,
                   format: { with: NAME_FORMAT, message: "must start with a letter or digit, then letters, digits, dashes, and underscores" }

  # Port and health are the app's defaults, carried into the app form. Mirror
  # what the box enforces (steward validateState) so a bad value fails here — with a
  # clear message, before the act — not cryptically at deploy time. Both optional:
  # blank means "no app default", and the box falls back (port 8080, health "/").
  validates :port, numericality: { only_integer: true, greater_than_or_equal_to: 1024,
                                    less_than_or_equal_to: 65535 }, allow_nil: true
  # Health is a URL path Caddy probes — it must start with "/".
  validates :health, format: { with: %r{\A/}, message: "must start with /" }, allow_blank: true

  # The app's declared inputs — *names only*, no values (values are supplied at app).
  #   env          : [{ "key" => "PASSWORD", "secret" => true }, …]  — secret? = off-record.
  #   secret_files : [{ "name" => "config", "path" => "/etc/zot/config.json" }, …] — mounted.
  # "secrets are env vars": a secret is just an env entry delivered off-record (the box
  # mirrors this — env vs Secret=type=env). Files are separate because they're mounted.
  validate :env_well_formed
  validate :secret_files_well_formed
  validate :release_well_formed
  validate :accessories_well_formed
  validate :processes_well_formed

  # env / secret_files / release default to [] (DB default), guard against a stray nil.
  def env = self[:env] || []
  def secret_files = self[:secret_files] || []

  # The command Steward runs once from the new image before the new container starts —
  # `bin/rails db:migrate` and its cousins. **argv, not a shell string**: the box execs it
  # directly, so a multi-step release belongs in a script inside the image, where the
  # image digest covers what it does (blueprint/steward/deploy.md, "The Release Step").
  #
  # It lives on the App because it is a property of the image the way port and health
  # are. An app copies it at create, so editing the library never silently changes
  # what an already-placed app runs on its next deploy.
  def release = self[:release] || []

  # The containers this app needs on the same box and that nothing else may reach — a
  # database, a cache. Subordinate by construction: no hostname, never routed, on a
  # network only this app joins (decisions/accessories-belong-to-one-app.md).
  #
  # Shape matches the box's spec exactly, so the envelope is a copy rather than a
  # translation: `{ "name", "image", "env" => {}, "secrets" => [], "volumes" => [] }`.
  def accessories = self[:accessories] || []

  def accessory_names = accessories.filter_map { |a| a["name"] }

  # The app's other containers — a worker, a clock. **The same image, env, secrets and
  # volumes**, running a different command; only the command differs, and that is the
  # point. A worker deployed separately could land on a different digest from the web
  # process, and a worker running yesterday's code against today's enqueued jobs is a
  # failure the record cannot describe (steward/internal/app/process.go).
  #
  # `command` is argv — the box execs it, so it never meets a shell.
  def processes = self[:processes] || []

  def process_names = processes.filter_map { |p| p["name"] }

  # The env var names this app declares (both plain and secret).
  def env_keys = env.filter_map { |e| e["key"] }

  # The declaration split by what actually happens to the value, sorted, for the
  # verification lists on the app page. The editor is a single run of chips you toggle,
  # which is quick but hard to *audit* — the mistake that matters is a variable that
  # should have been marked secret and wasn't, and its value is then written to an
  # append-only record where it cannot be taken back. Two sorted columns make that
  # mistake something you can scan for rather than something you have to notice.
  def env_recorded = env.reject { |e| e["secret"] }.filter_map { |e| e["key"] }.sort
  def env_off_record = env.select { |e| e["secret"] }.filter_map { |e| e["key"] }.sort
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

  # The box refuses a control character in the release command, because the value is
  # rendered into a record entry and an error message. Refuse it here, where it is typed,
  # rather than at the far end after someone has built an app on it — the same shape
  # as the digest-pin rule on Version.
  def release_well_formed
    return errors.add(:release, "must be a list") unless release.is_a?(Array)
    return if release.empty?

    unless release.all? { |a| a.is_a?(String) }
      return errors.add(:release, "must be a list of strings — the program, then its arguments")
    end
    if release.first.to_s.strip.empty?
      errors.add(:release, "starts with a blank — the first entry is the program to run")
    end
    if release.any? { |a| a.match?(/[\u0000-\u001f\u007f]/) }
      errors.add(:release, "contains a control character")
    end
  end

  # Mirrors the box's `validProcesses`, including the collision check: colours, processes
  # and accessories all mint container names from the app's, and two landing on one name
  # would have each silently overwrite the other's unit file.
  def processes_well_formed
    return errors.add(:processes, "must be a list") unless processes.is_a?(Array)

    seen = []
    processes.each do |p|
      unless p.is_a?(Hash) && p["name"].is_a?(String)
        return errors.add(:processes, "each process needs a name")
      end
      n = p["name"]
      errors.add(:processes, "#{n.inspect} must start with a letter or digit, then letters, digits, dashes, and underscores") unless n.match?(NAME_FORMAT)
      errors.add(:processes, "#{n} can't share the app's own name") if n == name
      errors.add(:processes, "#{n} is listed twice") if seen.include?(n)
      seen << n

      command = Array(p["command"])
      if command.empty?
        errors.add(:processes, "#{n} has no command — that is the only thing that makes it one")
      elsif command.any? { |a| !a.is_a?(String) || a.match?(/[\u0000-\u001f\u007f]/) }
        errors.add(:processes, "#{n}: the command must be a list of plain strings")
      end
    end
    container_names_are_distinct
  end

  # Every container this app will ever create on a box, checked for duplicates in one
  # place — the same shape the box checks, and for the same reason.
  def container_names_are_distinct
    claimed = {}
    claim = lambda do |container, what|
      if (prev = claimed[container])
        errors.add(:processes, "#{prev} and #{what} would both be container #{container.inspect}")
      end
      claimed[container] = what
    end

    %w[a b].each do |color|
      claim.call("#{name}-#{color}", "the #{color} colour")
      process_names.each { |n| claim.call("#{name}-#{n}-#{color}", "process #{n}") }
    end
    accessory_names.each { |n| claim.call("#{name}-#{n}", "accessory #{n}") }
  end

  # Mirrors the box's `validAccessories`, so a bad declaration fails where it is typed
  # rather than at deploy. The rules that matter are the ones that would otherwise
  # collide with something already on the box, or fail confusingly much later.
  def accessories_well_formed
    return errors.add(:accessories, "must be a list") unless accessories.is_a?(Array)

    seen = []
    accessories.each do |a|
      unless a.is_a?(Hash) && a["name"].is_a?(String)
        return errors.add(:accessories, "each accessory needs a name")
      end
      n = a["name"]
      errors.add(:accessories, "#{n.inspect} must start with a letter or digit, then letters, digits, dashes, and underscores") unless n.match?(NAME_FORMAT)
      # `a` and `b` are the app's deploy colors on the box, so an accessory by either
      # name would render a unit file that collides with a color's.
      errors.add(:accessories, "#{n} is a deploy color — pick another name") if %w[a b].include?(n)
      errors.add(:accessories, "#{n} can't share the app's own name") if n == name
      errors.add(:accessories, "#{n} is listed twice") if seen.include?(n)
      seen << n
      accessory_image_well_formed(n, a["image"])
      Array(a["volumes"]).each do |v|
        if (message = App.volume_error(v))
          errors.add(:accessories, "#{n}: #{message}")
        end
      end
      Array(a["secrets"]).each do |sec|
        errors.add(:accessories, "#{n}: #{sec.inspect} is not a valid env name") unless sec.to_s.match?(ENV_NAME)
      end
    end
  end

  # The same pin a Version needs, for the same reason: a tag means something different
  # tomorrow, and "which database was running" has to have an answer. Both halves — the
  # marker's presence and the digest's shape — because one without the other admits
  # `postgres:16`, which is exactly the hole the box's own test caught.
  def accessory_image_well_formed(name, image)
    image = image.to_s
    return errors.add(:accessories, "#{name} has no image") if image.blank?
    return errors.add(:accessories, "#{name}: image must be digest-pinned — ref@sha256:…") unless image.include?("@sha256:")

    hex = image.split("@sha256:", 2).last.to_s
    errors.add(:accessories, "#{name}: digest must be 64 hex characters") unless hex.match?(/\A[0-9a-f]{64}\z/)
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
