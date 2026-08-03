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
drifted = install!(acme, "acme-web", machine: crit, image: "ghcr.io/acme/web@sha256:want999",
                   hostname: "acme.example", port: 8080, health: "/up", drift: true)
failed  = install!(acme, "acme-api", machine: gone, image: "ghcr.io/acme/api@sha256:broken",
                   status: "failed", hostname: "api.acme.example")
install!(globex, "globex-site", machine: crit, image: "ghcr.io/globex/site@sha256:old", status: "retired")

label!(acme, "tier", "gold")
label!(acme, "env", "prod")

event!(actor: "operator@console.test", action: "linked machine", machine: gone, project: acme,
       summary: "Linked web-1 to Acme", at: 10.days.ago)
event!(actor: "ci-deployer", action: "deployed", machine: gone, install: failed, project: acme,
       summary: "Deploy acme-api failed: health check never passed", at: 2.days.ago,
       outcome: "failed", detail: "container exited 1 before /up returned 200")
event!(actor: "operator@console.test", action: "applied updates", machine: warn, project: acme,
       summary: "apt upgrade on db-1 failed", at: 1.day.ago,
       outcome: "failed", detail: "sudo: a password is required")
event!(actor: "ci-deployer", action: "deployed", machine: crit, install: drifted, project: acme,
       summary: "Deploying acme-web @sha256:want999", at: 20.minutes.ago,
       outcome: "pending") # issued, never settled — honest "outcome unknown"
event!(actor: "snapshot.timer", action: "observed", machine: warn,
       summary: "Status sample ingested", at: 3.minutes.ago)

library_app!("nginx", image: "docker.io/nginxinc/nginx-unprivileged", tag: "v1",
             port: 8080, health: "/", description: "Unprivileged nginx — the unprivileged-port app contract demo.")

report!
