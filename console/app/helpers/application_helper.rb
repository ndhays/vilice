module ApplicationHelper
  # Appearance, for the <html> element. Signed out there is no operator to have a
  # preference, so the default theme following the OS is the honest answer — it is
  # also what the login page wants.
  def current_theme = Theme.find(Current.user&.theme)
  def current_mode  = Current.user&.mode || "system"

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
  # One solid dot, read at a glance. The shape differs per state as well as the
  # colour — filled / slashed / hollow — so the meaning survives without colour
  # (blueprint/design/tokens.md: status colour is never the only signal).
  MACHINE_STATUS_ICON = {
    "reachable"   => { icon: "circle-filled", klass: "ok",    word: "Reachable" },
    "unreachable" => { icon: "circle-cut",    klass: "bad",   word: "Unreachable" },
    "unknown"     => { icon: "circle-hollow", klass: "muted", word: "Not yet seen" }
  }.freeze
  def machine_status_icon(machine)
    s = MACHINE_STATUS_ICON.fetch(machine.status)
    icon_tip(s[:icon], s[:word], size: 19, css_class: "row-icon status-ico #{s[:klass]}")
  end

  # What the box is *for*, as a single trailing glyph beside the scope marker.
  # Today that is only the balancer role, which is the one role Steward Console
  # stores (decisions/one-primitive-composed.md: a role over Machine). The role the
  # box itself reports needs ingestion before it can appear in a list — see
  # decisions/open/ui-roadmap.md — so this says what we actually know.
  def role_icon(machine)
    if machine.balancer?
      hosts = machine.fronted_host_count
      icon_tip("network", "Load Balancer — #{pluralize(hosts, 'host')}",
               size: 13, css_class: "role-ico")
    else
      apps = machine.app_count
      tip  = apps.positive? ? "Host — #{pluralize(apps, 'app')}" : "Host"
      icon_tip("hard-drive", tip, size: 13, css_class: "role-ico")
    end
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
    icon_tip(s[:icon], s[:word], size: 13, css_class: "scope-ico")
  end

  # ── The box's role ──────────────────────────────────────────────────────────
  # What a box was prepared as — `host` (runs apps) or `balancer` (fronts others).
  # It is the box's own fact and it is **set once**: `steward prepare <role>` writes
  # it, and re-preparing into the other role is refused (blueprint/steward/provision.md).
  # So it renders as a statement, never a control — the console used to offer a "Make
  # this a balancer" button, which wrote a column the box had never agreed to.
  #
  # The live read is the source when we have one; the stored column is our mirror of
  # the last read, and is what the fleet list can afford to show. A box we have never
  # reached has no role — *unknown*, which is not "host".
  ROLE_BADGE = {
    "balancer" => { icon: "network",    word: "Prepared as a balancer — fronts other boxes, runs no containers" },
    "host"     => { icon: "hard-drive", word: "Prepared as a host — runs apps" }
  }.freeze

  # Three states, and they are not the same thing:
  #   the box said so        → the role, live
  #   the box said nothing   → *not prepared* — we asked and it has no role file
  #   we could not ask       → *unknown*, falling back to the last read we mirrored
  def machine_role(machine, status = nil)
    return status.role.presence if status&.online?
    machine.last_seen_at.present? ? (machine.balancer? ? "balancer" : "host") : nil
  end

  def machine_role_icon_name(machine, status = nil)
    ROLE_BADGE.dig(machine_role(machine, status), :icon) || "circle-help"
  end

  def machine_role_badge(machine, status = nil)
    role = machine_role(machine, status)

    if role.nil? && status&.online?
      # Reached it, and it named no role: it has never been prepared. A different
      # fact from never having reached it, and it has a fix the operator can run.
      return tag.span("not prepared", class: "badge role-unprepared",
                      title: "This box has no role — run `steward prepare <role>` on it")
    elsif role.nil?
      return tag.span("role unknown", class: "badge role-unknown",
                      title: "Not read yet, so what this box was prepared as is unknown")
    end

    stale = status&.online? ? nil : " (last known)"
    tag.span(safe_join([ icon(ROLE_BADGE.dig(role, :icon), size: 13), role ], " "),
             class: "badge role-#{role}", title: "#{ROLE_BADGE.dig(role, :word)}#{stale}")
  end

  # A button's label when it sends a steward command: the mark, then the verb. The
  # mark says "this is a call into Steward" before you read the word; the word is the
  # one you would type. Filled (inverse) by `.btn.cmd` so it cannot pass for a link.
  def steward_verb(verb)
    safe_join([ render("shared/mark", size: 18), tag.span(verb, class: "cmd-verb") ])
  end

  # The stamp an entry leads with: the steward verb it ran, drawn like the button that
  # sends it (`steward_verb`) but flat — a record of a press, not a thing to press.
  def act_stamp(item)
    mark = item.via == :local ? icon("terminal", size: 14) : render("shared/mark", size: 16)
    tag.span(safe_join([ mark, tag.span(item.verb, class: "cmd-verb") ]),
             class: "act-stamp via-#{item.via.to_s.dasherize}")
  end

  # When the status on screen was read — reads are cached, so "live" needs its age.
  def read_age(status)
    return "Cached" if status.read_at.blank?
    at = status.read_at
    tag.time("Read #{time_ago_in_words(at)} ago · cached", datetime: at.iso8601, title: l(at, format: :long))
  end

  # The role as a plain fact for the machine page's facts line — the same three
  # states as the badge, in words: the role, *not prepared*, or *unknown*.
  def machine_role_word(machine, status = nil)
    role = machine_role(machine, status)
    if role
      stale = status&.online? ? "" : " (last known)"
      tag.span("#{role}#{stale}", title: ROLE_BADGE.dig(role, :word))
    elsif status&.online?
      tag.span("not prepared", class: "fact-gap", title: "This box has no role — run `steward prepare <role>` on it")
    else
      tag.span("unknown", class: "muted", title: "Not read yet, so what this box was prepared as is unknown")
    end
  end

  # A long image reference, shown short and copyable. The digest is the thing you
  # actually compare, and the full ref is 80+ characters that shouldered the columns
  # either side of it out of the row. Click copies the **whole** reference, not the
  # truncation — copying an abbreviation would be worse than not offering it.
  def digest_chip(image)
    return tag.span("—", class: "muted") if image.blank?

    tag.button(type: "button", class: "digest-chip mono", title: image,
               data: { controller: "clipboard", clipboard_text_value: image,
                       action: "click->clipboard#copy" }) do
      safe_join([ tag.span(short_image(image), class: "digest-text"),
                  icon("copy", size: 12, css_class: "icon digest-copy"),
                  icon("check", size: 12, css_class: "icon digest-done") ])
    end
  end

  # A command to run, with a copy button. Every command the console shows is meant to
  # be pasted into a shell on a box, so none of them should have to be selected by
  # hand — a `steward authorize` line carries a whole public key, and a half-selected
  # one fails in a way that is tedious to diagnose.
  #
  # The same shape as the docs site's blocks (blueprint/design/patterns.md): a real
  # <button> with an aria-label and an aria-hidden icon, not a click handler on the
  # <pre>. Copies the exact text, so what you paste is what is shown.
  def command_block(command, label: "Copy command")
    return if command.blank?

    tag.div(class: "cmd-block") do
      safe_join([
        tag.pre(command, class: "raw cmd"),
        tag.button(type: "button", class: "cmd-copy", "aria-label": label, title: label,
                   data: { controller: "clipboard", clipboard_text_value: command,
                           action: "click->clipboard#copy" }) do
          safe_join([ icon("copy", size: 14, css_class: "icon cmd-copy-idle"),
                      icon("check", size: 14, css_class: "icon cmd-copy-done") ])
        end
      ])
    end
  end

  # ── The Access ledger ───────────────────────────────────────────────────────
  # How far one key reaches, as a leading glyph. The scope rungs reuse SCOPE_ICON, so
  # a key's scope draws the same everywhere in the app. An ungated line is not a rung
  # — it is the absence of a ceiling — so it wears the alert, in the bad colour.
  REACH_ICON = {
    "ungated" => { icon: "triangle-alert", klass: "bad",
                   word: "No forced command — this key reaches the box without passing the gate" }
  }.freeze

  def access_reach_icon(line)
    r = REACH_ICON[line.reach]
    r ||= { icon: SCOPE_ICON.dig(line.reach, :icon) || "circle-help",
            klass: "reach-#{line.reach}", word: SCOPE_ICON.dig(line.reach, :word) || "Unknown scope" }
    icon_tip(r[:icon], r[:word], size: 16, css_class: "row-icon reach-ico #{r[:klass]}")
  end

  # The same word as a badge, for the axes where reach is not the heading.
  def access_reach_badge(line)
    return tag.span("ungated", class: "badge reach-ungated") if line.ungated?
    tag.span(line.reach.presence || "unknown", class: "badge reach-#{line.reach}")
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

  # State-forward badge, on the Install page. Reads `Install#state` — the one ladder
  # (blueprint/console/interface.md). It used to compute its own, shallower one that
  # knew only failed/deploying/pending/running/unplaced, so the *deep-dive* page for
  # an install was the least accurate thing about it: a drifted install, or one whose
  # box had gone unreachable, read here as plainly "running".
  INSTALL_STATE_LABEL = {
    "unplaced"    => "not placed",
    "unreachable" => "machine unreachable"
  }.freeze

  def install_state_badge(install)
    state = install.state
    tag.span(INSTALL_STATE_LABEL.fetch(state, state), class: "badge state-#{state}",
             title: INSTALL_STATUS.dig(state, :word))
  end

  # ── The intention, rendered as a gap ───────────────────────────────────────
  # "asked for 3 · serving 2" — the two halves side by side, never merged into one
  # number and never styled as a status badge
  # (decisions/drift-is-surfaced-never-closed.md: an intention never renders as state).
  # The asked-for half is marked as a claim; the serving half is what the boxes report.
  # Returns nil when in step and single-placement — the common case earns no chrome.
  def placement_gap_line(install, verbose: false)
    gap = install.placement_gap
    return if gap.zero? && install.count == 1 && !verbose

    asked   = tag.span("asked for #{pluralize(install.count, 'box')}", class: "intent-asked")
    serving = tag.span("serving #{install.serving_count}", class: "intent-serving")
    tag.span(safe_join([ asked, " · ", serving ], ""),
             class: "intent-line #{gap.zero? ? 'in-step' : (gap.negative? ? 'short' : 'over')}",
             title: placement_gap_word(install))
  end

  def placement_gap_word(install)
    gap = install.placement_gap
    return "In step — as many boxes serving as were asked for." if gap.zero?
    return "Short by #{gap.abs} — fewer boxes serving than were asked for. Closing this is an act." if gap.negative?

    "#{gap} more serving than were asked for. Removing one is an act."
  end

  # How each `Install#state` draws: the glyph that leads the install row, its colour,
  # and the precise word on the tooltip. The state ladder — and the honesty note about
  # what it is built from — lives with the logic, on `Install`.
  INSTALL_STATUS = {
    "failed"      => { icon: "circle-x",       klass: "bad",   word: "Failed" },
    "unreachable" => { icon: "circle-x",       klass: "bad",   word: "Machine unreachable" },
    "drift"       => { icon: "triangle-alert", klass: "warn",  word: "Drift — running an image other than desired" },
    "deploying"   => { icon: "clock",          klass: "warn",  word: "Deploying" },
    "pending"     => { icon: "clock",          klass: "warn",  word: "Pending" },
    "running"     => { icon: "circle-check",   klass: "ok",    word: "Running" },
    "unplaced"    => { icon: "circle-dot",     klass: "muted", word: "Not placed" }
  }.freeze

  # The leading glyph for an install row. Sits in the row-icon slot but carries its
  # own status colour and the precise word as a tooltip. The state itself is
  # `Install#state` — domain logic, so it lives on the model where the grouping and
  # the Status page can read the same ladder.
  def install_status_icon(install)
    s = INSTALL_STATUS.fetch(install.state)
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
    label = icon ? safe_join([ icon(icon, size: size), text ]) : text
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
    unless record && record[:ok]
      # Not "off" — unreachable. The box's own record is the witnessed half, and a
      # reader who cannot tell "we could not read it" from "there is nothing" is
      # being misled about the one thing this page exists to show.
      return tag.p(class: "integrity bad") do
        safe_join([ icon("circle-cut", size: 14),
                    "Box record unavailable — the entries below end at the last read." ], " ")
      end
    end
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
    tag.span(class: "health-line#{mod}") do
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

  # `event_kind` lived here: a hand-kept list of substrings that decided whether an
  # entry's glyph went amber. It is gone with the amber. The list was the kind of
  # thing that rots without failing — `updated` had already fallen out of it, so
  # apply-updates was quietly drawing as an observe — and it was guessing at
  # something the record can eventually be asked directly (the box record carries a
  # real scope). Nothing replaces it, because nothing needed it: a witnessed act is
  # marked by its `witnessed` tag and its outcome, in words.

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

  # What an act touched, without the verb. `action` and `summary` are two columns —
  # the verb and its object — and the entry renders them as two parts of one
  # sentence. Entries recorded before they were kept apart lead with the verb
  # ("Deployed acme-web on devbox"); the record is append-only, so the duplicate is
  # dropped here rather than rewritten. Returns "" when nothing is left, which is
  # also the case for an entry whose summary was only ever the verb.
  def act_detail(item)
    verb, summary = item.action.to_s, item.summary.to_s
    # Try the whole verb, then just its first word — an entry recorded under the old
    # "linked machine" still leads its summary with "Linked" alone.
    [ verb, verb.split.first ].compact.reject(&:blank?).uniq.each do |lead|
      stripped = summary.sub(/\A#{Regexp.escape(lead)}\b[\s:—-]*/i, "")
      return stripped.strip unless stripped == summary
    end
    summary.strip
  end

  def event_icon_name(item) = action_icon_name(item.action)

  # The glyph for a verb. Taken by name rather than by entry so the Record's action
  # filter can wear the same glyph the entries do — a pill and the rows it selects
  # should not be two different vocabularies for one word.
  # The verbs are single words (`updated`, `authorized`, `linked`), but the older
  # two-word spellings are still matched: the record is append-only, so entries
  # written before the rename keep their recorded verb and must still draw right.
  def action_icon_name(action)
    case action.to_s.downcase
    when "updated", /applied update/ then "check-check"
    when /deploy/                    then "rocket"
    when /rollback|rolled/           then "rotate-cw"
    when /restart|start/             then "play"
    when /stop/                      then "square"
    when /remov/                     then "trash-2"
    when /authoriz|revok|grant/      then "key-round"
    when /label/                     then "tag"
    when /observ|snapshot|status/    then "activity"
    when /link/                      then "link"
    when /imported|exported/         then "file-up"
    when /added/                     then "plus"
    when /edited|restated/           then "pencil"
    when /star/                      then "star"
    when /placed/                    then "map-pin"
    when /promoted|demoted|routed/   then "network"
    when /transferred|released/      then "handshake"
    when /restricted/                then "lock"
    when /opened/                    then "lock-open"
    when "set"                       then "settings-2"
    else                                  "circle-dot"
    end
  end
end
