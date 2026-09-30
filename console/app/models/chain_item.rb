# One line of the displayed chain — the merge of the two records
# (decisions/two-records.md), in a single shape the timeline can render:
#
#   - from a Steward Console Event   → an act Steward Console authored (a human behind it),
#   - from a Steward record entry → a box act; authored if Steward Console's own client
#     issued it, otherwise only witnessed (a direct CLI, the timer, another plane).
#
# A presentation value, not persisted.
#
# Each also carries its exact form, for the entry's lower levels: the `command` that ran
# (nil when nothing was run — an act recorded here only, or a step a command noted about
# itself), the `output` the box replied with, and `entry` — the record entry as stored.
#
# A box entry is one of three kinds (`kind`), and only one of them is a command:
#   :command — a verb someone invoked; the command is read straight off the entry
#   :refusal — Steward refused an attempt (`scope: deny`); `action` is the reason and
#              the first arg, when present, is the verb that was refused
#   :step    — a note a command wrote about its own work (`prepare` sets the role and
#              authorizes the binary; `deploy` records the spec). Not a command anyone
#              ran, so it never gets one — it is folded under the command it belongs to.
ChainItem = Struct.new(:at, :actor, :action, :summary, :origin, :machine, :project,
                       :outcome, :detail, :command, :output, :entry, :kind,
                       :box_entry, :steps, :repeats, :first_at, keyword_init: true) do
  # The actions Steward writes that are not commands (steward/internal: core.Record
  # call sites outside dispatch). Kept by hand; an unknown action reads as a command,
  # which is what nearly every entry is.
  STEP_ACTIONS = {
    "prepare-role"     => "role set to",
    "authorize-binary" => "binary authorized",
    "deploy-spec"      => "spec recorded for"
  }.freeze

  def self.from_event(event)
    new(
      at: event.at, actor: event.actor, action: event.action,
      summary: event.summary.presence || event.action,
      origin: :authored, machine: event.machine, project: event.project,
      outcome: event.outcome, detail: event.detail, kind: :command,
      command: event.raw&.dig("command").presence&.then { |c| "steward #{c}" },
      output: event.output,
      entry: event.attributes.except("raw", "output").merge("command" => event.raw&.dig("command")).compact
    )
  end

  # `client` is the name Steward Console's own scoped key records under; an entry under
  # that name is one Steward Console issued (authored), anything else is witnessed.
  def self.from_record_entry(entry, client:)
    action, args = entry["action"].to_s, Array(entry["args"])
    base = {
      at: (Time.zone.parse(entry["time"].to_s) rescue nil) || Time.current,
      actor: entry["actor"], origin: entry["actor"] == client ? :authored : :witnessed,
      entry: entry
    }
    if entry["scope"] == "deny"
      refused = args.first
      new(**base, kind: :refusal, action: "refused", outcome: "refused",
          summary: [ refused, "— #{action.delete_prefix('deny').delete_prefix(':').tr('-', ' ').presence || 'not authorized'}" ].compact.join(" "),
          command: refused && "steward #{refused}")
    elsif STEP_ACTIONS.key?(action)
      new(**base, kind: :step, action: action,
          summary: [ STEP_ACTIONS[action], *args.map { |a| abbreviate(a) } ].join(" "))
    else
      # The box records the verb and the arguments it was given, so the command is read
      # straight off the entry. (Output flags such as --json are not part of the act,
      # and the box does not record them.)
      new(**base, kind: :command, action: action,
          summary: [ action, *args.map { |a| abbreviate(a) } ].join(" "),
          command: [ "steward", action, *args ].join(" "))
    end
  end

  # A public key or a digest is one very long token; in the plain line it is shortened
  # from the middle. The command and the raw entry keep it whole.
  def self.abbreviate(arg)
    s = arg.to_s
    return s if s.length <= 32
    # "ssh-ed25519 AAAA…" keeps its type, then the blob shortened; a comment survives.
    s.split(" ").map { |t| t.length > 24 ? "#{t[0, 10]}…#{t[-6..]}" : t }.join(" ")
  end

  def witnessed? = origin == :witnessed
  def refusal? = kind == :refusal
  def step? = kind == :step

  # The steward verb the command ran — `apply-updates` — which is what the button that
  # sent it said. Nil when nothing was run.
  def verb = command.to_s.split[1]

  # How the act reached the box, which is what the entry's stamp shows:
  #   :console — sent by this console (a button was pressed)
  #   :local   — run on the box itself, not through a scoped key. Steward records a
  #              local invocation under `operator` (core.ActorName) — a person at the
  #              shell, or anything else run there without naming itself.
  #   :key     — another scoped key: CI, an agent, another console
  #   nil      — nothing was run
  LOCAL_ACTOR = "operator"
  def via
    return nil if verb.nil? || refusal?
    return :console unless witnessed?
    actor == LOCAL_ACTOR ? :local : :key
  end

  # Free-text search over an assembled chain. The machine page's record is the merge
  # of two sources — our events and the box's own entries — so it cannot be filtered
  # with a relation; it is filtered here, over what an entry actually says.
  def matches?(query)
    return true if query.blank?
    [ actor, action, summary ].compact.join(" ").downcase.include?(query.downcase)
  end

  # A routine status sample, from either record — the box's own timer entries
  # arrive here the same way Steward Console's do. Judged by the same rule as
  # `Event.acts`, so one definition covers both streams.
  def status? = Event::STATUS_ACTIONS.include?(action.to_s.downcase)

  # The same entry again, for collapsing a run of repeats into one line.
  def same_as?(other)
    other && kind == other.kind && actor == other.actor && action == other.action &&
      summary == other.summary && origin == other.origin
  end
end
