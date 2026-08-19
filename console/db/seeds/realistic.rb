# realistic — the dev-data world (SCENARIO=realistic). Additive and idempotent (no
# wipe): an operator to sign in as, the dev box, the live loopback box when its key
# exists, a couple of projects, and a little activity so the feed isn't empty. The
# default scenario is `empty`; this is the one to load when you want real data.
include Scenario

operator!

# The dev box (memory: devbox = root@5.78.218.105). If an observe key is sitting
# at /tmp/sy_key (the heartbeat proof's key), fold it in so reads work live.
key_path = ENV.fetch("STEWARD_SSH_KEY", "/tmp/sy_key")
devbox = Machine.find_or_initialize_by(name: "devbox")
devbox.assign_attributes(
  ssh_host: ENV.fetch("STEWARD_SSH_HOST", "5.78.218.105"),
  ssh_user: ENV.fetch("STEWARD_SSH_USER", "root"),
  scope: "observe"
)
devbox.ssh_private_key = File.read(key_path) if File.exist?(key_path) && devbox.ssh_private_key.blank?
devbox.save!

# A *live* local box, reached over loopback SSH — "Steward Console runs anywhere", so
# localhost is just one more Machine. Present only when the local observe key
# (set up by the dev harness) exists; this is what makes the round trip real.
if File.exist?(key_path)
  this_box = Machine.find_or_initialize_by(name: "this-box")
  this_box.assign_attributes(
    ssh_host: ENV.fetch("STEWARD_LOCAL_HOST", "localhost"),
    ssh_user: ENV.fetch("STEWARD_LOCAL_USER", ENV.fetch("USER", "root")),
    # operate so the mutate ceremony is demoable locally. The loopback key is only
    # observe-scoped, so a real Confirm settles *failed* — an honest demo. Observe
    # reads are unaffected (scope is our record of the key's rights, not the gate).
    scope: "operate"
  )
  this_box.ssh_private_key = File.read(key_path) if this_box.ssh_private_key.blank?
  this_box.save!
  # A few pending updates so the operate machine shows the Apply Updates act by default.
  label!(this_box, "fake-updates", "5")
end

acme = project!("Acme", contact_name: "Wile E. Coyote", contact_email: "wile@acme.test", starred: true)
project!("Globex", contact_name: "Hank Scorpio")

link!(acme, devbox)

if acme.installs.none?
  install = acme.installs.create!(name: "acme-web", image: "ghcr.io/acme/web@sha256:dedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedf", hostname: "acme.example")
  install.install_targets.create!(machine: devbox, strategy: "single", status: "running",
                                  desired_image: install.image, current_image: install.image)
end

if Event.none?
  install = acme.installs.first
  event!(actor: "operator@console.test", action: "linked",
         machine: devbox, project: acme, summary: "devbox to Acme", at: 3.days.ago)
  event!(actor: "operator@console.test", action: "authorized",
         machine: devbox, project: acme, summary: "ci-deployer at operate on devbox", at: 2.days.ago)
  event!(actor: "ci-deployer", action: "deployed", machine: devbox,
         install: install, project: acme, summary: "acme-web @sha256:dedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedf", at: 26.hours.ago)
  event!(actor: "ci-deployer", action: "restarted", machine: devbox,
         install: install, project: acme, summary: "acme-web on devbox", at: 90.minutes.ago)
end

# A Steward Console-own act on this-box, so its chain shows the *merge*: this authored
# entry alongside the box's own (witnessed) record read live over the loopback.
# Also an app on the box, so the mutate ceremony's lifecycle acts have a target.
if (tb = Machine.find_by(name: "this-box"))
  if tb.events.none?
    event!(actor: "operator@console.test", action: "linked",
           machine: tb, summary: "this-box", at: 2.days.ago)
  end
  if tb.installs.none?
    app = acme.installs.find_or_create_by!(name: "console") do |i|
      i.image = "ghcr.io/console/console@sha256:dedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedfdedf"
      i.hostname = "console.local"
    end
    app.install_targets.find_or_create_by!(machine: tb) do |t|
      t.strategy = "single"
      t.status = "running"
      t.desired_image = app.image
      t.current_image = app.image
    end
  end
end

# Example labels — the universal key/value system, shared by projects and machines.
label!(acme, "tier", "gold")
label!(acme, "env", "prod")
label!(project!("Globex"), "tier", "free")
label!(devbox, "env", "staging")
label!(devbox, "region", "eu")
if (this_box = Machine.find_by(name: "this-box"))
  label!(this_box, "env", "dev")
  label!(this_box, "role", "control-plane")
  label!(this_box, "shared")
end

# App Library — the shared catalog, plus the self-deploy proof this scenario is for.
library!
library_app!("console", image: demo_pin("ghcr.io/console/console"), tag: "v0.1",
             release: [ "bin/rails", "db:migrate" ],
             port: 3000, health: "/up",
             description: "Steward Console itself — the self-deploy proof.")

report!
