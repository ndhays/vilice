# Shared builders for the scenario seeds (see db/seeds/README.md).
#
# Each scenario file (all_clear.rb, all_broken.rb, …) is loaded by db/seeds.rb and
# builds a whole, self-consistent world through these helpers. Health (online/
# load/mem/disk) isn't stored — it's served at request time by the fake-observe
# seam from each machine's `fake-health` label, so `machine!(… health: "crit")`
# is all it takes to make a box read critical. Boot with VILICE_FAKE_OBSERVE=1.
module Scenario
  module_function

  # Children before parents, so delete_all is safe whether or not the DB enforces
  # foreign keys. Users/sessions are deliberately kept.
  WIPE = [ Event, Label, Placement, App, Version, AppTemplate, ProjectMachine, Machine, Project, Setting ].freeze

  # Start from a known-empty slate (every scenario but `realistic` calls this), so
  # contradictory worlds never overlap — and clear the observe cache so no stale
  # live read survives. A no-op outside dev/test: `empty` is the default scenario,
  # so plain `db:seed`/`db:reset` run this, and it must never wipe a production DB.
  def reset!
    return unless Rails.env.local?
    WIPE.each(&:delete_all)
    Rails.cache.clear
  end

  def operator!
    User.find_or_create_by!(email_address: "operator@console.test") { |u| u.password = "password" }
  end

  def project!(name, **attrs)
    Project.find_or_create_by!(name: name) { |p| p.assign_attributes(attrs) }
  end

  # A box. `health` becomes its fake-health label (nil = no fake health). last_seen
  # and status default to "freshly seen, online" — override for stale/broken worlds.
  def machine!(name, health: "ok", labels: {}, **attrs)
    m = Machine.find_or_initialize_by(name: name)
    m.assign_attributes({
      ssh_host: "#{name}.fake", ssh_user: "_vilice", scope: "observe",
      last_seen_at: Time.current, status: "reachable", vilice_version: PlatformVersion
    }.merge(attrs))
    m.save!
    label!(m, "fake-health", health) if health
    labels.each { |k, v| label!(m, k.to_s, v) }
    m
  end

  def link!(project, machine)
    # First project to link owns the box (mirrors registering from a project). A
    # shared box (sharing: everyone/list) then permits the later links.
    machine.update!(owner: project) if machine.owner.nil?
    ProjectMachine.find_or_create_by!(project: project, machine: machine)
  end

  # An app deployed onto a box. `drift: true` makes the running image lag the
  # desired one (the honest "not in sync" state); `status:` is the target's state.
  def app!(project, name, machine:, image:, status: "running", drift: false, **attrs)
    app = project.apps.find_or_create_by!(name: name) do |i|
      i.assign_attributes({ image: image, hostname: "#{name}.example" }.merge(attrs))
    end
    app.placements.find_or_create_by!(machine: machine) do |t|
      t.strategy      = "single"
      t.status        = status
      t.desired_image = image
      t.current_image = drift ? "#{image.split('@').first}@sha256:34ace00034ace00034ace00034ace00034ace00034ace00034ace00034ace000" : image
    end
    app
  end

  # A recorded act. Pass `outcome:` ("ok"/"failed"/"pending") to make it a mutate
  # entry; ok/failed are written already-settled, pending stays unsettled (the
  # honest "issued but never learned the result").
  def event!(actor:, action:, at:, outcome: nil, **attrs)
    extra = {}
    extra[:finished_at] = at if outcome && outcome != "pending"
    Event.record!(actor: actor, action: action, at: at, outcome: outcome, **extra, **attrs)
  end

  def label!(record, key, value = nil)
    l = record.labels.find_or_initialize_by(key: key)
    l.update!(value: value)
  end

  # A demo pin. `Version` refuses an unpinned image because the box does
  # (`deploy.go`: "image must be digest-pinned"), so seed data has to satisfy the same
  # rule as anything typed into the form — a catalog the app can't save is not a
  # rehearsal of the app. The digest is fabricated and derived from the ref, so it is
  # stable across reseeds and visibly not a real release: it always starts `5eed`.
  # Nothing in a scenario is pullable anyway — the machines are fake too.
  def demo_pin(ref) = "#{ref}@sha256:5eed#{Digest::SHA256.hexdigest(ref)[4..]}"

  def library_app!(name, image:, tag:, **attrs)
    app = AppTemplate.find_or_create_by!(name: name) { |a| a.assign_attributes(attrs) }
    if app.versions.none?
      v = app.versions.create!(tag: tag, image: image)
      app.set_latest!(v)
    end
    app
  end

  # A stocked App Library, so the app flow has something real to run through.
  # Chosen to cover every shape the app form has to handle rather than to be a
  # recommended list: no inputs at all, plain env, secret env, a mounted secret
  # file, and a service that is not HTTP (no health path — nothing for Caddy to
  # probe). Ports are all >= 1024: the box refuses anything lower, and the AppTemplate
  # model mirrors that so it fails here with a sentence instead of at deploy.
  #
  # Every release carries a **tag and a digest**, because that is what a release is
  # here: the tag is the name a human reads, the digest is what actually gets pulled.
  # The console can resolve the first into the second for you — once, into the field —
  # and never again afterwards (decisions/a-tag-is-not-a-release.md). These digests are
  # fabricated, so they are not what a lookup would return for these real refs.
  def library!
    library_app!("nginx", image: demo_pin("docker.io/nginxinc/nginx-unprivileged"), tag: "v1",
                 port: 8080, health: "/",
                 description: "Unprivileged nginx — the unprivileged-port app contract demo.")

    library_app!("gitea", image: demo_pin("docker.io/gitea/gitea"), tag: "v1.22",
                 port: 3000, health: "/api/healthz",
                 description: "Git hosting with a web UI. Small enough for one box.",
                 env: [ { "key" => "GITEA__server__ROOT_URL", "secret" => false },
                        { "key" => "GITEA__database__PASSWD", "secret" => true } ])

    library_app!("uptime-kuma", image: demo_pin("docker.io/louislam/uptime-kuma"), tag: "v1",
                 port: 3001, health: "/",
                 description: "Uptime monitoring. No inputs — deploy and open it.")

    library_app!("grafana", image: demo_pin("docker.io/grafana/grafana"), tag: "v11",
                 port: 3000, health: "/api/health",
                 description: "Dashboards over your metrics.",
                 env: [ { "key" => "GF_SERVER_ROOT_URL", "secret" => false },
                        { "key" => "GF_SECURITY_ADMIN_PASSWORD", "secret" => true } ])

    library_app!("miniflux", image: demo_pin("docker.io/miniflux/miniflux"), tag: "v2",
                 port: 8080, health: "/healthcheck",
                 description: "A quiet RSS reader. Wants a database URL and an admin password.",
                 env: [ { "key" => "ADMIN_USERNAME", "secret" => false },
                        { "key" => "DATABASE_URL", "secret" => true },
                        { "key" => "ADMIN_PASSWORD", "secret" => true } ])

    library_app!("vaultwarden", image: demo_pin("docker.io/vaultwarden/server"), tag: "v1",
                 port: 8080, health: "/alive",
                 description: "Password vault. The admin token is off-record, on stdin.",
                 env: [ { "key" => "DOMAIN", "secret" => false },
                        { "key" => "ADMIN_TOKEN", "secret" => true } ])

    # The secret-*file* case: a whole config mounted into the container, never a
    # value on a command line. The App model's own docs use this example.
    library_app!("zot", image: demo_pin("docker.io/project/zot"), tag: "v2",
                 port: 5000, health: "/v2/",
                 description: "An OCI registry. Its config arrives as a mounted secret file.",
                 secret_files: [ { "name" => "config", "path" => "/etc/zot/config.json" } ])

    # Not HTTP: no health path, because there is nothing for Caddy to probe. Blank
    # is a legitimate answer here, not missing data.
    library_app!("redis", image: demo_pin("docker.io/library/redis"), tag: "v7", port: 6379,
                 description: "In-memory store. Not an HTTP service — no health path.")

    library_app!("postgres", image: demo_pin("docker.io/library/postgres"), tag: "v16", port: 5432,
                 description: "The database. Not HTTP either; its password is off-record.",
                 env: [ { "key" => "POSTGRES_DB", "secret" => false },
                        { "key" => "POSTGRES_USER", "secret" => false },
                        { "key" => "POSTGRES_PASSWORD", "secret" => true } ])
  end

  def report!
    name = ENV.fetch("SCENARIO", "empty")
    puts "Seeded [#{name}]: #{Project.count} projects, #{Machine.count} machines, " \
         "#{App.count} apps, #{AppTemplate.count} apps, #{Event.count} events."
    puts "Sign in: operator@console.test / password"
    puts "Boot with VILICE_FAKE_OBSERVE=1 for live health (or use bin/scenario)."
  end

  # The platform VERSION, read once (the repo-root single source of truth).
  PlatformVersion = (Rails.root.join("../VERSION").read.strip rescue "dev")
end
