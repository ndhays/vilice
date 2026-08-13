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

library!

n = 0
PROJECTS.times do |p|
  project = project!("Project #{format('%02d', p + 1)}",
                     contact_name: "Owner #{p + 1}", starred: p.zero?)
  label!(project, "tier", %w[gold silver free][p % 3])
  label!(project, "env", %w[prod staging dev][p % 3])

  # Every third project fronts its apps with a balancer — a role over Machine, not a
  # new noun (decisions/one-primitive-composed.md). Enough of them to see the "Edge"
  # grouping mean something, and few enough that most boxes still sit behind one.
  edge =
    if (p % 3).zero?
      e = machine!("edge-#{format('%02d', p + 1)}", health: "ok", scope: "operate",
                   balancer: true, status: "reachable", last_seen_at: 2.minutes.ago,
                   labels: { role: "edge", region: %w[eu us ap][p % 3] })
      link!(project, e)
      e
    end

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
      # Where there's an edge box, the app sits behind it — which is what makes a
      # count above one honest (decisions/one-primitive-composed.md).
      behind = edge ? { exposure: "balanced", balancer: edge } : {}
      install!(project, "app-#{p}-#{i}", machine: machine, image: img,
               hostname: "app-#{p}-#{i}.example", drift: drift, status: status, **behind)
    end
  end
end

# A long record so the Record view and its filters have something to chew on.
# Acts only — status samples are the other stream (`Snapshot`), never chain rows.
actors  = %w[operator@console.test ci-deployer alice@console.test]
# Verb + object, kept apart the way the record keeps them: the action column is one
# word, the summary is what it touched (blueprint/console/interface.md).
actions = %w[deployed restarted updated linked authorized]
machines = Machine.order(:name).to_a
projects = Project.order(:name).to_a
installs = Install.order(:name).to_a
200.times do |k|
  outcome = %w[ok ok ok failed pending][k % 5] if k.even?
  box     = machines[k % machines.size]
  install = installs[k % installs.size]
  project = projects[k % projects.size]
  verb    = actions[k % actions.size]
  # The summary is the *object* — the verb lives in the action column beside it, and
  # repeating it here is what made every entry read "Deployed deployed…".
  detail =
    case verb
    when "authorized" then "ci-deployer at operate on #{box.name}"
    when "updated"    then box.name
    when "linked"     then "#{box.name} to #{project.name}"
    else                   "#{install.name} on #{box.name}"
    end
  event!(actor: actors[k % actors.size], action: verb,
         machine: box, project: project,
         summary: detail, at: (k * 37).minutes.ago, outcome: outcome,
         detail: (outcome == "failed" ? "exit 1" : nil))
end

report!
