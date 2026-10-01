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
  Act = Struct.new(:verb, :label, :past, :target, :compose, :build, keyword_init: true) do
    def app_scoped? = target == :app
    def compose? = compose == true
  end

  ACTS = {
    "apply-updates" => Act.new(verb: "apply-updates", label: "Apply Updates",
                               past: "updated", target: :machine,
                               build: ->(_m, _i) { "apply-updates --json" }),
    "restart"       => Act.new(verb: "restart", label: "Restart", past: "restarted",
                               target: :app,
                               build: ->(_m, i) { "restart #{i.name} --json" }),
    "stop"          => Act.new(verb: "stop", label: "Stop", past: "stopped",
                               target: :app,
                               build: ->(_m, i) { "stop #{i.name} --json" }),
    "start"         => Act.new(verb: "start", label: "Start", past: "started",
                               target: :app,
                               build: ->(_m, i) { "start #{i.name} --json" }),
    # Deploy needs a compose step (pick the image digest) and ships the desired-state
    # envelope on stdin; rollback is parameterless (the box re-runs its PrevImage).
    "deploy"        => Act.new(verb: "deploy", label: "Deploy", past: "deployed",
                               target: :app, compose: true,
                               build: ->(_m, i) { "deploy #{i.name} --json" }),
    "rollback"      => Act.new(verb: "rollback", label: "Roll back", past: "rolled back",
                               target: :app,
                               build: ->(_m, i) { "rollback #{i.name} --json" }),
    # Destructive: takes the app off the box (units, secrets, route). The
    # ceremony's preview+confirm is the guard.
    "remove"        => Act.new(verb: "remove", label: "Remove", past: "removed",
                               target: :app,
                               build: ->(_m, i) { "remove #{i.name} --json" }),
    # The balancer's table, applied. Machine-scoped: it is about this box's edge, not
    # about one app. The table rides stdin and is *derived* at send time from the
    # apps that select this balancer — never stored, so it cannot drift from the
    # placements it describes (decisions/one-primitive-composed.md). Applying is an act
    # because nothing converges on its own
    # (decisions/drift-is-surfaced-never-closed.md).
    "route"         => Act.new(verb: "route", label: "Apply Routing", past: "routed",
                               target: :machine,
                               build: ->(_m, _i) { "route --json" }),
  }.freeze

  # The app-lifecycle acts, in the order they read on the machine page.
  LIFECYCLE = %w[start stop restart].freeze

  attr_reader :act, :machine, :app, :actor, :params

  # The command an act sends, from its name alone — for places that show or send it
  # without a stored App to bind: the machine page's Operate zone, and the box-app
  # deploy/remove that keeps no App row. One builder, so the command a page
  # shows is the command that is sent.
  AppRef = Data.define(:name)
  def self.command(verb, machine, name: nil)
    ACTS.fetch(verb.to_s).build.call(machine, name && AppRef.new(name: name))
  end

  # Resolve a verb to a bound Mutation — or nil if the verb is unknown or an
  # app-scoped act names no (valid) app on this machine. `params` carries the
  # compose inputs (image/hostname/port/health) for deploy.
  def self.build(verb, machine:, actor:, app_id: nil, params: {})
    act = ACTS[verb.to_s]
    return nil unless act

    app = act.app_scoped? ? machine.apps.find_by(id: app_id) : nil
    return nil if act.app_scoped? && app.nil?

    new(act, machine: machine, app: app, actor: actor, params: params)
  end

  def initialize(act, machine:, app:, actor:, params: {})
    @act = act
    @machine = machine
    @app = app
    @actor = actor
    @params = (params || {}).to_h.symbolize_keys
  end

  def needs_compose? = act.compose?
  # A compose act is ready once the operator has picked an image; others always are.
  def composed? = !needs_compose? || image.present?

  def command = act.build.call(machine, app)

  # Two acts ship desired state on stdin: deploy sends one app's spec, route sends the
  # whole edge table. Both are derived at send time rather than read from a stored copy.
  def stdin
    case act.verb
    when "deploy" then composed? ? app.deploy_envelope(image: image, hostname: hostname, port: port, health: health).to_json : nil
    when "route"  then RoutingTable.envelope(machine).to_json
    end
  end

  def action = act.past

  def summary
    case act.verb
    when "deploy"   then "#{app.name} on #{machine.name} @#{short_digest}"
    when "rollback" then "#{app.name} on #{machine.name}"
    when "route"    then route_summary
    else
      app ? "#{app.name} on #{machine.name}" : machine.name
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
                  outcome: "pending", command: "vilice #{command}")
  end
end
