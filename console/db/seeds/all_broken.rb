# all_broken — everything wrong, every failure mode at once. One box gone, one
# critical (with hardening drift), one under pressure; apps drifted or failed; a
# deploy that failed and one that's still pending (issued, outcome never learned);
# stale last_seen. The stress test for error states, empty-of-good-news views, and
# accessibility of the loud/red paths.
include Scenario

reset!
operator!

acme   = project!("Acme",   contact_name: "Wile E. Coyote", contact_email: "wile@acme.test", starred: true)
globex = project!("Globex", contact_name: "Hank Scorpio")

# A box that's gone, a critical box (hardening drift too), and one under pressure.
gone = machine!("web-1", health: "offline", scope: "operate", status: "unreachable",
                last_seen_at: 9.days.ago, labels: { env: "prod" })
crit = machine!("web-2", health: "crit", scope: "operate", status: "reachable",
                sharing: "everyone", last_seen_at: 12.minutes.ago, labels: { env: "prod" })
warn = machine!("db-1", health: "warn", scope: "observe", status: "reachable",
                last_seen_at: 1.hour.ago, labels: { env: "prod", role: "database" })

[ gone, crit, warn ].each { |m| link!(acme, m) }
link!(globex, crit)

# Drifted (running image lags desired), failed, and a retired remnant.
drifted = app!(acme, "acme-web", machine: crit, image: "ghcr.io/acme/web@sha256:7ae49997ae49997ae49997ae49997ae49997ae49997ae49997ae49997ae49997",
                   hostname: "acme.example", port: 8080, health: "/up", drift: true)
failed  = app!(acme, "acme-api", machine: gone, image: "ghcr.io/acme/api@sha256:b2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fbeeb2fb",
                   status: "failed", hostname: "api.acme.example")
app!(globex, "globex-site", machine: crit, image: "ghcr.io/globex/site@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf", status: "retired")

label!(acme, "tier", "gold")
label!(acme, "env", "prod")

event!(actor: "operator@console.test", action: "linked", machine: gone, project: acme,
       summary: "web-1 to Acme", at: 10.days.ago)
event!(actor: "ci-deployer", action: "deployed", machine: gone, app: failed, project: acme,
       summary: "acme-api on web-1", at: 2.days.ago,
       outcome: "failed", detail: "container exited 1 before /up returned 200")
event!(actor: "operator@console.test", action: "updated", machine: warn, project: acme,
       summary: "db-1", at: 1.day.ago,
       outcome: "failed", detail: "sudo: a password is required")
event!(actor: "ci-deployer", action: "deployed", machine: crit, app: drifted, project: acme,
       summary: "acme-web @sha256:7ae49997ae49997ae49997ae49997ae49997ae49997ae49997ae49997ae49997", at: 20.minutes.ago,
       outcome: "pending") # issued, never settled — honest "outcome unknown"

library!

report!
