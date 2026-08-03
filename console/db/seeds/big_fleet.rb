# big_fleet — a large, deterministic fleet and a long record. For exercising list
# search/sort/pagination, dense-table accessibility, and the Record view at volume.
# Health is spread across the bands in a fixed rotation, so the same fleet renders
# the same way every run.
include Scenario

reset!
operator!

PROJECTS = 8
MACHINES_PER_PROJECT = 6
BANDS = %w[ok ok ok warn crit offline].freeze # weighted toward healthy

library_app!("nginx", image: "docker.io/nginxinc/nginx-unprivileged", tag: "v1",
             port: 8080, health: "/", description: "Unprivileged nginx.")
library_app!("redis", image: "docker.io/library/redis", tag: "v7", port: 6379,
             description: "In-memory data store.")

n = 0
PROJECTS.times do |p|
  project = project!("Project #{format('%02d', p + 1)}",
                     contact_name: "Owner #{p + 1}", starred: p.zero?)
  label!(project, "tier", %w[gold silver free][p % 3])
  label!(project, "env", %w[prod staging dev][p % 3])

  MACHINES_PER_PROJECT.times do |i|
    n += 1
    health = BANDS[n % BANDS.size]
    machine = machine!("node-#{format('%03d', n)}", health: health,
                       scope: i.even? ? "operate" : "observe",
                       status: health == "offline" ? "unreachable" : "reachable",
                       last_seen_at: (health == "offline" ? 5.days : (n % 30).minutes).ago,
                       labels: { env: %w[prod staging dev][p % 3], region: %w[eu us ap][i % 3] })
    link!(project, machine)

    if i < 3 # the first few boxes in each project run an app
      img = "ghcr.io/fleet/app#{p}-#{i}@sha256:img#{format('%04d', n)}"
      drift = health == "crit"
      status = health == "offline" ? "failed" : "running"
      install!(project, "app-#{p}-#{i}", machine: machine, image: img,
               hostname: "app-#{p}-#{i}.example", drift: drift, status: status)
    end
  end
end

# A long record so the Record view and its filters have something to chew on.
actors  = %w[operator@console.test ci-deployer alice@console.test snapshot.timer]
actions = %w[deployed restarted applied\ updates linked\ machine authorized\ client observed]
machines = Machine.order(:name).to_a
projects = Project.order(:name).to_a
200.times do |k|
  outcome = %w[ok ok ok failed pending][k % 5] if k.even?
  event!(actor: actors[k % actors.size], action: actions[k % actions.size],
         machine: machines[k % machines.size], project: projects[k % projects.size],
         summary: "Event #{k} on the fleet", at: (k * 37).minutes.ago, outcome: outcome,
         detail: (outcome == "failed" ? "exit 1" : nil))
end

report!
