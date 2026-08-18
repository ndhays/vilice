class HomeController < ApplicationController
  # Status — the home page. Calm by default; lead with exceptions. The unit of
  # concern is the install (what serves a client), so we surface installs in a
  # bad-but-actionable state — failed, machine-unreachable, or drift. Transient
  # states (deploying/pending) and healthy installs stay quiet. Unreachable
  # machines get their own section as the *root cause*: one down box explains many
  # down installs, and it's fixed at the machine.
  #
  # That is the whole page: what needs you, or nothing. It carried a "Latest" feed
  # of recent acts too, which made the healthy case — the common one — read as a
  # wall of things already dealt with. The record is a destination of its own, one
  # click away in the rail, and it is better at being one.
  #
  # A **placement gap** counts as needing a look too — three boxes asked for and two
  # serving is exactly the actionable-but-not-broken case this page exists for. It stays
  # a separate test rather than another `Install#state` value on purpose: an intention
  # is not a state (decisions/drift-is-surfaced-never-closed.md), and the row renders it
  # as a gap beside the health glyph, not inside it.
  def index
    installs = Install.includes(:app, :version, :project, install_targets: :machine)
    ranked = installs.map { |i| [ i, i.state ] }

    unhealthy = ranked.select { |_, state| Install::EXCEPTION_STATES.include?(state) }
                      .sort_by { |_, state| Install::EXCEPTION_STATES.index(state) }
                      .map(&:first)
    # Short of the intention. An install serving *more* boxes than asked for is a gap
    # too, but not an outage — it stays off the exceptions list and shows on the install.
    short = ranked.map(&:first).select { |i| i.placement_gap.negative? }

    @problem_installs = (unhealthy + short).uniq

    # Being short and being *able to do something about it* are different asks: one is a
    # click, the other is go get a box. The page already separates unreachable machines
    # as a root cause for the same reason — a fix that lives somewhere else earns its own
    # line. Computed against one preloaded pool, because a list must not ask the database
    # once per row.
    pool = Machine.operate.includes(:project_machines).order(:name)
    @stuck_installs = short.reject { |i| i.candidate_machines(pool).any? }

    @down_machines = Machine.order(:name).select(&:seen_unreachable?)

    @machine_count = Machine.count
    @install_count = Install.count
  end
end
