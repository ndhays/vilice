# all_clear — a healthy fleet. Every box reachable and calm, every app in sync,
# every recent act settled ok, records intact, boxes hardened. The baseline for
# "what good looks like" and a clean canvas for accessibility passes.
include Scenario

reset!
operator!

acme    = project!("Acme",    contact_name: "Wile E. Coyote", contact_email: "wile@acme.test", starred: true)
globex  = project!("Globex",  contact_name: "Hank Scorpio")
initech = project!("Initech", contact_name: "Bill Lumbergh")

web1 = machine!("web-1", health: "ok", scope: "operate", labels: { env: "prod", region: "eu" })
web2 = machine!("web-2", health: "ok", scope: "operate", sharing: "everyone", labels: { env: "prod", region: "us" })
db1  = machine!("db-1",  health: "ok", scope: "observe", labels: { env: "prod", role: "database" })

[ web1, web2 ].each { |m| link!(acme, m) }
link!(globex, web2)
link!(initech, db1)

w = install!(acme, "acme-web",   machine: web1, image: "ghcr.io/acme/web@sha256:clean01", hostname: "acme.example", port: 8080, health: "/up")
install!(acme,   "acme-worker",  machine: web2, image: "ghcr.io/acme/worker@sha256:clean02")
install!(globex, "globex-site",  machine: web2, image: "ghcr.io/globex/site@sha256:clean03")

label!(acme, "tier", "gold")
label!(acme, "env", "prod")
label!(globex, "tier", "free")

# A calm, fully-settled history.
event!(actor: "operator@console.test", action: "linked machine", machine: web1, project: acme,
       summary: "Linked web-1 to Acme", at: 6.days.ago)
event!(actor: "operator@console.test", action: "authorized client", machine: web1, project: acme,
       summary: "Granted operate to ci-deployer", at: 5.days.ago)
event!(actor: "ci-deployer", action: "deployed", machine: web1, install: w, project: acme,
       summary: "Deployed acme-web @sha256:clean01", at: 2.days.ago, outcome: "ok")
event!(actor: "ci-deployer", action: "applied updates", machine: web2, project: acme,
       summary: "apt upgrade on web-2", at: 20.hours.ago, outcome: "ok")
event!(actor: "operator@console.test", action: "restarted", machine: web1, install: w, project: acme,
       summary: "Restarted acme-web", at: 3.hours.ago, outcome: "ok")
event!(actor: "snapshot.timer", action: "observed", machine: db1,
       summary: "Status sample ingested", at: 4.minutes.ago)

library_app!("nginx", image: "docker.io/nginxinc/nginx-unprivileged", tag: "v1",
             port: 8080, health: "/", description: "Unprivileged nginx — the unprivileged-port app contract demo.")
library_app!("console", image: "ghcr.io/console/console", tag: "v0.1",
             port: 3000, health: "/up", description: "Steward Console itself — the self-deploy proof.")

report!
