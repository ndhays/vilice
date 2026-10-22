# A witnessed act the operator can issue through the ceremony. The registry is
# the single allowlist — a verb never comes from raw input; it's looked up here.
# Each act knows its past-tense fact for the record, whether it targets the whole
# machine or one app (App), whether it needs a compose step, and how to build
# the vilice command. This is the one seam future acts (reboot, …) extend.
#
# A Mutation instance binds an act to a machine/app/actor (+ any compose
# params) and can produce the exact record line the ceremony previews — so
# "confirm" shows precisely what will be written
# (decisions/open/ui-shape.md §"the mutate ceremony").
class Mutation
  Act = Struct.new(:key, :verb, :label, :past, :target, :compose, :build, keyword_init: true) do
    def app_scoped? = target == :app
    def compose? = compose == true
  end

  # A registry host, optionally with a port — the same rule the box applies
  # (`validRegistry`). Checked here too, because the value is written into a command.
  REGISTRY_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9._-]*(:\d+)?\z/

  # Keyed by the name the ceremony is asked for. `verb` is the vilice command the
  # button is named for; the two differ only where one command has two forms
  # (`backup <app>` and `backup --machine`). Each build takes the machine, the app
  # (anything with a name), and the act's own params.
  ACTS = {
    "apply-updates" => Act.new(verb: "apply-updates", label: "Apply Updates",
                               past: "updated", target: :machine,
                               build: ->(_m, _i, _p) { "apply-updates --json" }),
    "restart"       => Act.new(verb: "restart", label: "Restart", past: "restarted",
                               target: :app,
                               build: ->(_m, i, _p) { "restart #{i.name} --json" }),
    "stop"          => Act.new(verb: "stop", label: "Stop", past: "stopped",
                               target: :app,
                               build: ->(_m, i, _p) { "stop #{i.name} --json" }),
    "start"         => Act.new(verb: "start", label: "Start", past: "started",
                               target: :app,
                               build: ->(_m, i, _p) { "start #{i.name} --json" }),
    # Deploy needs a compose step (pick the image digest) and ships the desired-state
    # envelope on stdin; rollback is parameterless (the box re-runs its PrevImage).
    "deploy"        => Act.new(verb: "deploy", label: "Deploy", past: "deployed",
                               target: :app, compose: true,
                               build: ->(_m, i, _p) { "deploy #{i.name} --json" }),
    "rollback"      => Act.new(verb: "rollback", label: "Roll back", past: "rolled back",
                               target: :app,
                               build: ->(_m, i, _p) { "rollback #{i.name} --json" }),
    # Destructive: takes the app off the box (units, secrets, route). The
    # ceremony's preview+confirm is the guard.
    "remove"        => Act.new(verb: "remove", label: "Remove", past: "removed",
                               target: :app,
                               build: ->(_m, i, _p) { "remove #{i.name} --json" }),
    # Backups follow the app: its volumes and spec, to the box's restic repo. Restore
    # writes the latest snapshot back over the live data and redeploys.
    "backup"        => Act.new(verb: "backup", label: "Back up", past: "backed up",
                               target: :app,
                               build: ->(_m, i, _p) { "backup #{i.name} --json" }),
    "restore"       => Act.new(verb: "restore", label: "Restore", past: "restored",
                               target: :app,
                               build: ->(_m, i, _p) { "restore #{i.name} --json" }),
    # The box's own record, snapshotted off-box. The one backup that belongs to the
    # machine rather than to an app.
    "backup-record" => Act.new(verb: "backup", label: "Back up the record", past: "backed up",
                               target: :machine,
                               build: ->(_m, _i, _p) { "backup --machine --json" }),
    # The balancer's table, applied. Machine-scoped: it is about this box's edge, not
    # about one app. The table rides stdin and is *derived* at send time from the
    # apps that select this balancer — never stored, so it cannot drift from the
    # placements it describes (decisions/one-primitive-composed.md). Applying is an act
    # because nothing converges on its own
    # (decisions/drift-is-surfaced-never-closed.md).
    "route"         => Act.new(verb: "route", label: "Apply Routing", past: "routed",
                               target: :machine,
                               build: ->(_m, _i, _p) { "route --json" }),
    # Withdraw the box's login for a registry. Logging in is not here: it carries a
    # password, so it has its own form (Machines::RegistriesController).
    "registry-logout" => Act.new(verb: "registry-logout", label: "Log out", past: "logged out",
                                 target: :machine,
                                 build: ->(_m, _i, p) { "registry-logout #{p[:registry]} --json" })
  }.each { |key, act| act.key = key }.freeze

  # The app-lifecycle acts, in the order they read on the page.
  LIFECYCLE = %w[start stop restart].freeze

  # Acts that take something away. Their buttons are red.
  DANGER = %w[remove restore registry-logout].freeze
  def danger? = DANGER.include?(act.key)

  attr_reader :act, :machine, :app, :name, :actor, :params

  # The command an act sends, from its name alone — for places that show or send it
  # without a stored App to bind. One builder, so the command a page shows is the
  # command that is sent.
  AppRef = Data.define(:name)
  def self.command(key, machine, name: nil, params: {})
    ACTS.fetch(key.to_s).build.call(machine, name && AppRef.new(name: name), params)
  end

  # Resolve a key to a bound Mutation — or nil if it is unknown, or its input is not
  # one this console would write into a command.
  #
  # An app-scoped act names its app one of two ways. `app_id` is an App we hold a
  # placement for on this machine. `name` is an app the box reports that we may hold
  # nothing for (a machine-view deploy keeps no App) — everything but deploy works
  # from the name alone, since deploy needs a spec and only an App carries one.
  def self.build(key, machine:, actor:, app_id: nil, name: nil, params: {})
    act = ACTS[key.to_s]
    return nil unless act

    params = (params || {}).to_h.symbolize_keys
    app = nil
    if act.app_scoped?
      app = machine.apps.find_by(id: app_id) if app_id.present?
      app ||= machine.apps.find_by(name: name) if name.present?
      name = app&.name || name.to_s
      return nil unless name.match?(App::NAME_FORMAT)
      return nil if act.compose? && app.nil?
    else
      name = nil
    end
    return nil if key.to_s == "registry-logout" && !params[:registry].to_s.match?(REGISTRY_FORMAT)

    new(act, machine: machine, app: app, name: name, actor: actor, params: params)
  end

  def initialize(act, machine:, app:, actor:, name: app&.name, params: {})
    @act = act
    @machine = machine
    @app = app
    @name = name
    @actor = actor
    @params = (params || {}).to_h.symbolize_keys
  end

  def needs_compose? = act.compose?
  # A compose act is ready once the operator has picked an image; others always are.
  def composed? = !needs_compose? || image.present?

  def command = act.build.call(machine, name && AppRef.new(name: name), params)

  # Two acts ship desired state on stdin: deploy sends one app's spec, route sends the
  # whole edge table. Both are derived at send time rather than read from a stored copy.
  def stdin
    case act.key
    when "deploy" then composed? ? app.deploy_envelope(image: image, hostname: hostname, port: port, health: health).to_json : nil
    when "route"  then RoutingTable.envelope(machine).to_json
    end
  end

  def action = act.past

  def summary
    case act.key
    when "deploy"          then "#{name} on #{machine.name} @#{short_digest}"
    when "route"           then route_summary
    when "backup-record"   then "the record on #{machine.name}"
    when "registry-logout" then "#{machine.name} of #{params[:registry]}"
    else
      name ? "#{name} on #{machine.name}" : machine.name
    end
  end

  # The record line names what the edge will serve, not just that it was touched — "routed
  # db-1" tells a later reader nothing about what changed.
  def route_summary
    routes = machine.routing_table
    return "#{machine.name} — fronting nothing" if routes.empty?

    hosts = routes.flat_map(&:hostnames).join(", ")
    "#{machine.name} → #{hosts} across #{routes.sum { |r| r.upstreams.size }} upstreams"
  end

  # Compose fields — what the operator picks, each defaulting from the App.
  def image    = params[:image].presence
  def hostname = params[:hostname].presence || app&.hostname
  def port     = (params[:port].presence || app&.port)&.to_i
  def health   = params[:health].presence || app&.health

  # A short, human handle for the pinned image (the sha, trimmed).
  def short_digest
    digest = image.to_s[/sha256:([0-9a-f]+)/, 1] || image.to_s
    digest[0, 12]
  end

  # The exact line this act will write — render it in the preview so the confirm
  # step looks identical to the record entry it commits to.
  def preview_item
    ChainItem.new(at: Time.current, actor: actor, action: action, summary: summary,
                  origin: :authored, machine: machine, project: app&.project,
                  outcome: "preview", command: "vilice #{command}")
  end
end
