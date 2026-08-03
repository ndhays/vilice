class HomeController < ApplicationController
  # Status — the home page. Calm by default; lead with exceptions. The unit of
  # concern is the install (what serves a client), so we surface installs in a
  # bad-but-actionable state — failed, machine-unreachable, or drift. Transient
  # states (deploying/pending) and healthy installs stay quiet. Unreachable
  # machines get their own section as the *root cause*: one down box explains many
  # down installs, and it's fixed at the machine. The live head of the record stays
  # in eyeline; the full record lives on the Record page.
  EXCEPTION_STATUSES = %w[ failed unreachable drift ].freeze

  def index
    installs = Install.includes(:app, :version, :project, install_targets: :machine)
    @problem_installs = installs
      .map { |i| [ i, helpers.install_status(i) ] }
      .select { |_, status| EXCEPTION_STATUSES.include?(status) }
      .sort_by { |_, status| EXCEPTION_STATUSES.index(status) }
      .map(&:first)

    @down_machines = Machine.order(:name).select(&:seen_unreachable?)

    @recent = Event.latest.includes(:machine, :project, :install).limit(6)
                   .map { |e| ChainItem.from_event(e) }

    @machine_count = Machine.count
    @install_count = Install.count
  end
end
