module ApplicationHelper
  # Reachability badge — observe-side, reflects the last read from Steward.
  def status_badge(machine)
    label = machine.status.sub("unknown", "not yet seen")
    tag.span(label, class: "badge #{machine.status}")
  end

  # The scope a machine's key carries. observe = read-only (blue); operate =
  # can mutate (amber) — the same colour language as the panels.
  def scope_badge(machine)
    tag.span(machine.scope, class: "badge scope-#{machine.scope}")
  end

  # Reachability as a single leading glyph for the compact machine row — the one
  # thing you glance for (is it up). Reuses the .status-ico colours.
  MACHINE_STATUS_ICON = {
    "reachable"   => { icon: "circle-check", klass: "ok",    word: "Reachable" },
    "unreachable" => { icon: "circle-x",     klass: "bad",   word: "Unreachable" },
    "unknown"     => { icon: "circle-dot",   klass: "muted", word: "Not yet seen" }
  }.freeze
  def machine_status_icon(machine)
    s = MACHINE_STATUS_ICON.fetch(machine.status)
    tag.span(icon(s[:icon], size: 15), class: "row-icon status-ico #{s[:klass]}", title: s[:word])
  end

  # Scope as a compact, muted trailing glyph: observe = an eye (read), operate =
  # sliders (can act), grant = a key (can admit others). All the same quiet colour —
  # it's a marker, not a signal.
  SCOPE_ICON = {
    "observe" => { icon: "eye",        word: "Scope: OBSERVE (read-only)" },
    "operate" => { icon: "settings-2", word: "Scope: OPERATE (can act)" },
    "grant"   => { icon: "key-round",  word: "Scope: GRANT (can admit other keys)" }
  }.freeze
  def scope_icon(machine)
    s = SCOPE_ICON.fetch(machine.scope)
    tag.span(icon(s[:icon], size: 13), class: "scope-ico", title: s[:word])
  end

  # How a box is shared. Dedicated is the quiet default (no badge); everyone/list
  # are called out so cross-client sharing is visible (machine-ownership.md).
  SHARING_LABEL = { "everyone" => "shared · everyone", "list" => "shared · list" }.freeze
  def sharing_badge(machine)
    return if machine.sharing_dedicated?
    tag.span(SHARING_LABEL.fetch(machine.sharing), class: "badge shared")
  end

  # An unowned box has no home — surfaced so a released/fleet-registered box is
  # never lost (machine-ownership.md).
  def owner_badge(machine)
    return unless machine.unowned?
    tag.span("no owner", class: "badge unowned", title: "Transfer to an owner to use machine")
  end

  # The three sharing modes, as the operator sees them (label + one-line hint).
  SHARING_MODES = {
    "dedicated" => [ "Not shared", "Only the owner can use this box." ],
    "everyone"  => [ "Shared with everyone", "Any project may pick it up." ],
    "list"      => [ "Shared with a specific list", "The owner, plus the projects you allow." ]
  }.freeze
  def sharing_mode_label(mode) = SHARING_MODES.fetch(mode).first
  def sharing_mode_hint(mode)  = SHARING_MODES.fetch(mode).last

  # The address Steward Console dials. Host is what the operator gave (IP or name);
  # port shows only when it's not the SSH default. The user is always `steward`
  # (ceiling-is-the-machine) — noise on screen, so it's dropped here; the
  # connection still uses it.
  def ssh_address(machine)
    machine.ssh_port.to_i == 22 ? machine.ssh_host : "#{machine.ssh_host}:#{machine.ssh_port}"
  end

  # An install's state, rolled up from its live targets (retired ones don't count).
  # Severity order, so the worst-but-actionable state wins: failed → deploying →
  # pending → running. No live target = not yet placed on a box.
  INSTALL_STATE_ORDER = %w[ failed deploying pending running ].freeze

  def install_state(install)
    live = install.install_targets.reject(&:install_retired?).map(&:status)
    return "unplaced" if live.empty?
    INSTALL_STATE_ORDER.find { |s| live.include?(s) } || "running"
  end

  # State-forward badge for the install list — the protagonist of the row.
  def install_state_badge(install)
    state = install_state(install)
    tag.span(state == "unplaced" ? "not placed" : state, class: "badge state-#{state}")
  end

  # The install's rolled-up health as a single glyph — the at-a-glance signal that
  # leads the install row. Worst-but-actionable wins across live targets.
  #
  # HONESTY NOTE: this is built from *stored* state (the last deploy outcome,
  # last-seen reachability, and recorded image drift), NOT a fresh probe. Until
  # persistent ingestion lands (#6), "ok" means "last we knew". The precise word
  # rides the tooltip; don't let the glyph overclaim truth we don't have.
  INSTALL_STATUS = {
    "failed"      => { icon: "circle-x",       klass: "bad",   word: "Failed" },
    "unreachable" => { icon: "circle-x",       klass: "bad",   word: "Machine unreachable" },
    "drift"       => { icon: "triangle-alert", klass: "warn",  word: "Drift — running an image other than desired" },
    "deploying"   => { icon: "clock",          klass: "warn",  word: "Deploying" },
    "pending"     => { icon: "clock",          klass: "warn",  word: "Pending" },
    "running"     => { icon: "circle-check",   klass: "ok",    word: "Running" },
    "unplaced"    => { icon: "circle-dot",     klass: "muted", word: "Not placed" }
  }.freeze

  def install_status(install)
    targets = install.install_targets.reject(&:install_retired?)
    return "unplaced" if targets.empty?
    return "failed"      if targets.any?(&:install_failed?)
    return "unreachable" if targets.any? { |t| t.install_running? && t.machine.seen_unreachable? }
    return "drift"       if targets.any? { |t| t.install_running? && t.current_image.present? && !t.in_sync? }
    return "deploying"   if targets.any?(&:install_deploying?)
    return "pending"     if targets.any?(&:install_pending?)
    "running"
  end

  # The leading glyph for an install row. Sits in the row-icon slot but carries its
  # own status colour and the precise word as a tooltip.
  def install_status_icon(install)
    s = INSTALL_STATUS.fetch(install_status(install))
    tag.span(icon(s[:icon], size: 15), class: "row-icon status-ico #{s[:klass]}", title: s[:word])
  end

  # A short, human handle for a pinned image — the digest trimmed, or the ref as-is.
  def short_image(image)
    return "—" if image.blank?
    digest = image.to_s[/sha256:([0-9a-f]+)/, 1]
    digest ? "@#{digest[0, 12]}" : image.to_s
  end

  # The machine-id Steward Console knows itself by. In a real deployment Steward
  # injects STEWARD_SELF_MACHINE_ID when it deploys Steward Console (robust even
  # in a container that can't see the host's /etc/machine-id); on a co-resident
  # dev box we fall back to reading it directly. Blank when Steward Console runs off-box.
  def self_machine_id
    return @self_machine_id if defined?(@self_machine_id)
    @self_machine_id = ENV["STEWARD_SELF_MACHINE_ID"].presence ||
      (File.read("/etc/machine-id").strip rescue nil)
  end

  # "You are here" — the live read says this is the box Steward Console runs on.
  def you_are_here?(status)
    status.respond_to?(:here?) && status.here?(self_machine_id)
  end

  # A cheap self check for the fleet list (no per-machine live read): the box
  # Steward Console reaches over loopback is itself. The machine page confirms it
  # authoritatively by machine-id; here we just hint with a pin.
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 0.0.0.0].freeze

  def local_machine?(machine)
    LOOPBACK_HOSTS.include?(machine.ssh_host.to_s.strip.downcase)
  end

  # Render a record's labels as neutral metadata badges — `key` or `key=value`
  # (the value is machine truth, so it's mono). Distinct from the status/scope
  # badges, which carry meaning; labels are just tags you group and search by.
  def label_badges(record)
    return if record.labels.empty?
    tag.span(class: "labels") do
      safe_join(record.labels.sort_by(&:key).map { |l| label_badge(l) }, " ")
    end
  end

  def label_badge(label)
    tag.span(class: "label") do
      if label.value.present?
        safe_join([ tag.span(label.key, class: "lk"), tag.span(label.value, class: "lv") ])
      else
        tag.span(label.key, class: "lk")
      end
    end
  end

  # Labels for a compact list row — smaller, and capped so a heavily-tagged box
  # doesn't blow out the row. The overflow shows as a quiet "+N"; the full set is
  # on the detail page. Labels still earn their place when they're used.
  def compact_label_badges(record, limit: 3)
    return if record.labels.empty?
    labels = record.labels.sort_by(&:key)
    extra  = labels.size - limit
    badges = labels.first(limit).map { |l| label_badge(l) }
    badges << tag.span("+#{extra}", class: "label more") if extra.positive?
    tag.span(safe_join(badges, " "), class: "labels compact")
  end

  # A file-system-style path. Pass [label, path] pairs; the last is the current
  # location (rendered plain, not a link).
  def breadcrumb(crumbs)
    parts = crumbs.each_with_index.map do |(label, path), i|
      last = i == crumbs.size - 1
      if path && !last
        link_to(label, path, class: "crumb")
      else
        tag.span(label, class: "crumb current")
      end
    end
    tag.nav(safe_join(parts, tag.span("/", class: "crumb-sep")), class: "breadcrumb")
  end

  # A button-styled link with an optional leading icon — the icon+label pattern
  # repeated across the app. Pass the button class via :class (e.g. "btn", "btn-quiet").
  def button_link_to(text, path, icon: nil, size: 14, **opts)
    label = icon ? safe_join([ icon(icon, size: size), text ], " ") : text
    link_to label, path, **opts
  end

  # A page header: a title (with an optional icon) and a right-aligned actions area.
  # Pass the actions as a block.
  def page_header(title, icon: nil, &block)
    heading = icon ? tag.h1(safe_join([ icon(icon, size: 20), title ], " ")) : tag.h1(title)
    actions = block ? tag.span(capture(&block), class: "head-actions") : nil
    tag.div(safe_join([ heading, actions ].compact), class: "page-head")
  end

  # The chain-integrity line — un-bypassability made visible. The box's record is
  # hash-chained; this surfaces that it reads back unbroken (or that it doesn't).
  def record_integrity(record)
    return tag.p("Box record unreachable.", class: "integrity off") unless record && record[:ok]
    env = record.dig(:data, "data") || {}
    count = env["count"].to_i
    noun = count == 1 ? "entry" : "entries"
    if env["intact"]
      tag.p(class: "integrity ok") do
        safe_join([ icon("circle-check", size: 14), "record intact · #{count} #{noun} · chain verified" ], " ")
      end
    else
      tag.p(class: "integrity bad") do
        safe_join([ icon("triangle-alert", size: 14), "record broken — #{env['integrity']}" ], " ")
      end
    end
  end

  # The plain-language health line: a calm dot + one sentence. Loud only when
  # something is wrong (the old app's gem, recomputed from a live read).
  def health_line(status)
    mod = case status.health
          when :crit, :offline then " crit"
          when :warn then " warn"
          else ""
          end
    tag.div(class: "health-line#{mod}") do
      safe_join([ tag.span("", class: "dot dot-#{status.dot}"), status.narrative ], " ")
    end
  end

  # The hardening posture line: a dot + plain words, read from the fact the box
  # published. Never a live check — that needs root on the box; observe only reads
  # what was written. Gray when the box was never checked.
  def hardening_line(status)
    locked = status.hardened?
    text =
      if !status.hardening_known?
        "Hardening not checked"
      elsif locked
        "Hardened"
      else
        "Drifted: #{status.hardening_drift.join(", ")}"
      end
    # A lock, not a dot: locked + green = hardened, open + gray/amber = not.
    lock = tag.span(icon(locked ? "lock" : "lock-open", size: 14), class: "harden-lock #{status.hardening_dot}")
    parts = [ lock, text ]
    if status.hardening_checked_at.present?
      when_t = Time.zone.parse(status.hardening_checked_at) rescue nil
      parts << tag.span("· checked #{time_ago_in_words(when_t)} ago", class: "muted") if when_t
    end
    tip = "Posture is read from what the box published — refreshing it needs root: run `steward harden --check` on the box."
    tag.div(safe_join(parts, " "), class: "hardening-line", title: tip)
  end

  # What an event touched, as links — minus the entity whose page we're on
  # (`within`), so a machine's own chain doesn't link back to itself. An event's
  # machine is the box it happened *on at the time*; if an install later moves to
  # another box, its old entries keep pointing at the old machine — the record
  # shows the move as a sequence, it doesn't rewrite history.
  def event_context(event, within: nil)
    parts = []
    parts << link_to(event.machine.name, event.machine) if event.machine && event.machine != within
    parts << link_to(event.project.name, event.project) if event.project && event.project != within
    safe_join(parts, " · ") if parts.any?
  end

  # Acts that change something (a box, or Steward Console's own domain) read as
  # mutations; everything else is a quiet observe/system note. Works on an Event
  # or a ChainItem (both carry `action`). A heuristic on the verb for now — the
  # box record carries a real scope we could read instead.
  WITNESSED_VERBS = %w[deploy rollback roll start stop restart remove apply
                       authorize revoke grant link add create set store connect
                       label].freeze

  def event_kind(item)
    return :mutate if WITNESSED_VERBS.any? { |v| item.action.to_s.downcase.include?(v) }
    :observe
  end

  # The outcome of a witnessed act, settled on its own entry: pending acts read
  # "running", a settled act shows ok/failed (failed carries the box's reason).
  # Instantaneous acts and box-mirror entries have no outcome — nothing renders.
  def outcome_tag(item)
    case item.outcome
    when "pending"
      tag.span("running…", class: "outcome running")
    when "ok"
      tag.span(icon("circle-check", size: 12), class: "outcome ok", title: "succeeded")
    when "failed"
      tag.span(safe_join([ icon("circle-x", size: 12), "failed" ], " "),
               class: "outcome failed", title: item.detail.presence)
    end
  end

  def event_icon_name(item)
    case item.action.to_s.downcase
    when /deploy/                 then "box"
    when /rollback/               then "rotate-cw"
    when /start|restart/          then "play"
    when /stop|remove/            then "square"
    when /authorize|revoke|grant/ then "shield"
    when /label/                  then "tag"
    when /observ|snapshot|status/ then "activity"
    when /link/                   then "handshake"
    else                               "circle-dot"
    end
  end
end
