# How each thing about a box is. The machine page shows these as a row of chips in its
# quick view; the Machine Status page shows each in full as the heading of its part
# (blueprint/console/interface.md).
#
# A summary has to say enough that the reader need not go and look: `:ok` reads plain,
# `:warn` and `:bad` take the warning colours.
module MachineSectionsHelper
  # `text` is the full sentence, for the status page and for a tooltip. `short` is the
  # few words that fit a chip on the machine page; it defaults to the text.
  Summary = Data.define(:text, :level, :short) do
    def initialize(text:, level:, short: text) = super
  end

  # How full something is, as a compact bar: the label, the bar coloured by how close
  # it is to trouble, the percentage, and the amounts. Nil percent (a box that did not
  # report it) draws an empty bar rather than a guess.
  def usage_bar(label, percent:, level:, used:, total:, icon_name:)
    tag.div(class: "usage is-#{level}", title: "#{label}: #{percent || '—'}% used") do
      safe_join([
        tag.span(safe_join([ icon(icon_name, size: 13), label ], " "), class: "usage-label"),
        tag.span(percent ? "#{percent}%" : "—", class: "usage-pct"),
        tag.span("#{number_to_human_size(used, precision: 3)} of #{number_to_human_size(total, precision: 3)}", class: "usage-amount"),
        tag.span(tag.span("", class: "bar-fill", style: "width: #{percent.to_i.clamp(0, 100)}%"), class: "bar")
      ])
    end
  end

  # One thing about the box, as a chip on the machine page: an icon and a few words,
  # coloured when something is wrong, with the full sentence on hover. The chip is the
  # link to its part of the Machine Status page.
  def status_chip(machine, title, summary, anchor, icon_name)
    link_to status_machine_path(machine, anchor: anchor),
            class: "status-chip is-#{summary.level}", title: "#{title}: #{summary.text}" do
      safe_join([ icon(icon_name, size: 14), tag.span(summary.short) ])
    end
  end

  # ── An app's line ─────────────────────────────────────────────────────────
  # How much of the box's memory one app is using: a small bar and the amount. The bar
  # is a share of the box, since an app has no limit of its own to be measured against.
  # Nothing when the box does not say (an older vilice, or an app that is not running).
  def app_memory_bar(status, box_app)
    used = box_app["memory_bytes"].to_i
    return "".html_safe unless used.positive? && status.mem_total_bytes.positive?

    share = (100.0 * used / status.mem_total_bytes).round
    tag.span(class: "app-memory", title: "Using #{number_to_human_size(used, precision: 3)} — #{share}% of this box's memory") do
      safe_join([ tag.span(tag.span("", class: "bar-fill", style: "width: #{share.clamp(1, 100)}%"), class: "bar"),
                  tag.span(number_to_human_size(used, precision: 3), class: "app-memory-amount") ])
    end
  end

  # Two small marks on an app's line, quiet when all is well and coloured when not: its
  # certificates and its backup. Each says the whole thing on hover. A mark is absent
  # when there is nothing to judge — no hostname served, or a box that reports no backups.
  def app_cert_mark(status, name)
    certs = status.certs_for(name)
    return "".html_safe if certs.empty?

    level = %i[bad warn ok].find { |l| certs.any? { |c| c.level == l } }
    words = { ok: "#{pluralize(certs.size, 'certificate')} valid",
              warn: "A certificate expires within #{MachineStatus::CERT_WARN_DAYS} days",
              bad: "A certificate is not valid" }.fetch(level)
    tag.span(icon("shield", size: 14), class: "app-mark is-#{level}", title: words)
  end

  def app_backup_mark(status, name)
    row = status.backup_row(name)
    return "".html_safe if row.nil?

    level, words =
      if !status.backup_configured? then [ :warn, "Not backed up — no backup repo is set on this box" ]
      elsif row.failing?            then [ :bad, "Last backup failed #{time_ago_in_words(row.last_failed)} ago" ]
      elsif row.never?              then [ :warn, "Never backed up" ]
      else                               [ :ok, "Backed up #{time_ago_in_words(row.last_ok)} ago" ]
      end
    tag.span(icon("hard-drive", size: 14), class: "app-mark is-#{level}", title: words)
  end

  # A part of the Machine Status page: a card that leads with the same summary the
  # quick view showed, then the detail and the acts.
  def status_part(title, summary, anchor, &block)
    tag.section(class: "panel observe status-part is-#{summary.level}", id: anchor) do
      safe_join([
        tag.div(safe_join([ tag.h2(title, class: "kicker"), tag.span(summary.text, class: "status-summary") ]),
                class: "status-part-head"),
        capture(&block)
      ])
    end
  end

  def hardening_summary(status)
    return Summary.new(text: "Not checked", level: :ok, short: "Hardening not checked") unless status.hardening_known?
    return Summary.new(text: "Hardened", level: :ok) if status.hardened?

    Summary.new(text: "Drifted: #{status.hardening_drift.join(', ')}", level: :warn, short: "Hardening drifted")
  end

  def maintenance_summary(status)
    waiting = []
    waiting << "#{pluralize(status.update_count, 'update')} waiting" if status.updates_available?
    waiting << "restart required" if status.reboot_required?
    if waiting.any?
      short = status.updates_available? ? pluralize(status.update_count, "update") : "Restart required"
      return Summary.new(text: waiting.join(" · ").upcase_first, level: :warn, short: short)
    end

    window = status.maintenance_known? ? "daily at #{status.maintenance_time}" : "no maintenance window"
    Summary.new(text: "Up to date · #{window}", level: :ok, short: "Up to date")
  end

  def registries_summary(status)
    hosts = status.registries.map(&:host)
    Summary.new(text: hosts.any? ? hosts.join(", ") : "None", level: :ok,
                short: hosts.any? ? hosts.join(", ") : "No registries")
  end

  # Over the box's whole set, or one app's.
  def certs_summary(status, certs = status.certs)
    by = certs.group_by(&:level)
    bad, warn = by.fetch(:bad, []).size, by.fetch(:warn, []).size
    return Summary.new(text: "#{bad} not valid", level: :bad, short: "#{pluralize(bad, 'cert')} not valid") if bad.positive?
    return Summary.new(text: "#{warn} expiring soon", level: :warn, short: "#{pluralize(warn, 'cert')} expiring") if warn.positive?

    Summary.new(text: "#{certs.size} valid", level: :ok, short: "#{pluralize(certs.size, 'cert')} valid")
  end

  # ── An app's page ─────────────────────────────────────────────────────────
  # Up is well, and so is stopped — someone stopped it. Anything else is not.
  def app_running_summary(box_app)
    state = box_app["state"].to_s
    return Summary.new(text: "The box does not say", level: :ok) if state.blank?

    Summary.new(text: state.upcase_first, level: state.match?(/\A(up|running|stopped)\b/i) ? :ok : :bad)
  end

  def app_deploy_summary(box_app)
    image = box_app && box_app["image"].to_s
    return Summary.new(text: "Not deployed here", level: :ok) if image.blank?

    Summary.new(text: "Running #{short_image(image)}", level: :ok)
  end

  def app_backup_summary(status, row)
    return Summary.new(text: "Not backed up — no backup repo is set on this box", level: :warn) unless status.backup_configured?
    return Summary.new(text: "Last backup failed #{time_ago_in_words(row.last_failed)} ago", level: :bad) if row.failing?
    return Summary.new(text: "Never backed up", level: :warn) if row.never?

    Summary.new(text: "Backed up #{time_ago_in_words(row.last_ok)} ago", level: :ok)
  end

  # The chain, then the record's own backup — the one backup that is the machine's.
  def record_summary(status, record)
    return Summary.new(text: "Could not read the record", level: :bad, short: "Record unread") unless record && record[:ok]

    env = record.dig(:data, "data") || {}
    return Summary.new(text: "Chain broken", level: :bad, short: "Record chain broken") unless env["intact"]

    parts = [ "Intact", pluralize(env["count"].to_i, "entry") ]
    row = status.backup_row("machine")
    level, short = :ok, "Record intact"
    if row.nil?
      # A box too old to report backups: say nothing about them rather than guess.
    elsif !status.backup_configured?
      parts << "not backed up"
      level, short = :bad, "Record not backed up"
    elsif row.failing?
      parts << "last backup failed"
      level, short = :bad, "Record backup failed"
    elsif row.never?
      parts << "never backed up"
      level, short = :warn, "Record never backed up"
    else
      parts << "backed up #{time_ago_in_words(row.last_ok)} ago"
    end
    Summary.new(text: parts.join(" · "), level: level, short: short)
  end

  # A ledger that cannot be read, or a key with no forced command, is a problem; a
  # count of pinned keys is not.
  def access_summary(machine, actors)
    return Summary.new(text: "Could not read the ledger", level: :bad, short: "Access unread") unless actors.is_a?(Hash) && actors[:ok]

    lines = Array(actors.dig(:data, "data", "actors")).map { |a| AccessLine.from(machine, a) }
    ungated = lines.count(&:ungated?)
    if ungated.positive?
      return Summary.new(text: "#{pluralize(lines.size, 'key')} · #{ungated} with no forced command", level: :bad,
                         short: "#{pluralize(ungated, 'key')} ungated")
    end

    Summary.new(text: pluralize(lines.size, "key"), level: :ok)
  end
end
