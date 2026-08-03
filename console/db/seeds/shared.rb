# Shared builders for the scenario seeds (see db/seeds/README.md).
#
# Each scenario file (all_clear.rb, all_broken.rb, …) is loaded by db/seeds.rb and
# builds a whole, self-consistent world through these helpers. Health (online/
# load/mem/disk) isn't stored — it's served at request time by the fake-observe
# seam from each machine's `fake-health` label, so `machine!(… health: "crit")`
# is all it takes to make a box read critical. Boot with STEWARD_FAKE_OBSERVE=1.
module Scenario
  module_function

  # Children before parents, so delete_all is safe whether or not the DB enforces
  # foreign keys. Users/sessions are deliberately kept.
  WIPE = [ Event, Label, InstallTarget, Install, Version, App, ProjectMachine, Machine, Project, Setting ].freeze

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
      ssh_host: "#{name}.fake", ssh_user: "steward", scope: "observe",
      last_seen_at: Time.current, status: "reachable", steward_version: PlatformVersion
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
  def install!(project, name, machine:, image:, status: "running", drift: false, **attrs)
    install = project.installs.find_or_create_by!(name: name) do |i|
      i.assign_attributes({ image: image, hostname: "#{name}.example" }.merge(attrs))
    end
    install.install_targets.find_or_create_by!(machine: machine) do |t|
      t.strategy      = "single"
      t.status        = status
      t.desired_image = image
      t.current_image = drift ? "#{image.split('@').first}@sha256:stale000" : image
    end
    install
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

  def library_app!(name, image:, tag:, **attrs)
    app = App.find_or_create_by!(name: name) { |a| a.assign_attributes(attrs) }
    if app.versions.none?
      v = app.versions.create!(tag: tag, image: image)
      app.set_latest!(v)
    end
    app
  end

  def report!
    name = ENV.fetch("SCENARIO", "empty")
    puts "Seeded [#{name}]: #{Project.count} projects, #{Machine.count} machines, " \
         "#{Install.count} installs, #{App.count} apps, #{Event.count} events."
    puts "Sign in: operator@console.test / password"
    puts "Boot with STEWARD_FAKE_OBSERVE=1 for live health (or use bin/scenario)."
  end

  # The platform VERSION, read once (the repo-root single source of truth).
  PlatformVersion = (Rails.root.join("../VERSION").read.strip rescue "dev")
end
