require "test_helper"

# The four journeys, end to end: auth-gated, observe reads, and the witnessed
# mutate path. The SSH transport is stubbed so tests stay offline.
class JourneysTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @project  = Project.create!(name: "Acme", starred: true)
    @observer = Machine.create!(name: "obs", ssh_host: "10.0.0.3", ssh_private_key: "k", owner: @project)
    @operator = Machine.create!(name: "op", ssh_host: "10.0.0.4", scope: "operate", ssh_private_key: "k")
    ProjectMachine.create!(project: @project, machine: @observer)
  end

  test "everything is behind the login" do
    get root_path
    assert_redirected_to new_session_path
    get machines_path
    assert_redirected_to new_session_path
  end

  test "home, projects, and settings render when signed in" do
    sign_in_as @user
    Event.record!(actor: "alice", action: "deployed", machine: @observer, summary: "deployed nginx")
    get root_path
    assert_response :success
    assert_select "h1", /status/i
    # Status is an inbox, not a feed: with nothing wrong it says so, and the record
    # — including the act just written — stays at its own destination.
    assert_select ".all-clear", /Nothing to report/
    assert_select ".chain-entry", 0

    get record_path
    assert_response :success
    assert_select "h1", /record/i

    get projects_path
    assert_response :success
    get project_path(@project)
    assert_response :success
    assert_select "h1", /Acme/

    get settings_path
    assert_response :success
  end

  # The two streams stay apart on the surfaces that render a chain. A sample would
  # otherwise take the head of the record and report only that a timer looked.
  test "a status sample never reaches the Record page" do
    sign_in_as @user
    Event.record!(actor: "alice", action: "deployed", machine: @observer, summary: "deployed nginx")
    Event.record!(actor: "snapshot.timer", action: "observed", machine: @observer,
                  summary: "Status sample ingested")

    get record_path
    assert_response :success
    assert_select ".chain-entry", 1
    assert_select "body", text: /Status sample ingested/, count: 0
  end

  # blueprint/console/interface.md: "Every chain the UI renders goes through it."
  # The Install and Project pages did not, so a routine sample could take a slot on
  # the one page that is meant to show what *happened* to that install.
  test "a status sample never reaches the Install or Project record either" do
    sign_in_as @user
    install = @project.installs.create!(name: "chain-app")
    Event.record!(actor: "alice", action: "deployed", machine: @observer,
                  project: @project, install: install, summary: "chain-app on obs")
    Event.record!(actor: "snapshot.timer", action: "observed", machine: @observer,
                  project: @project, install: install, summary: "Status sample ingested")

    get install_path(install)
    assert_response :success
    assert_select ".chain-entry", 1
    assert_select "body", text: /Status sample ingested/, count: 0

    get project_path(@project)
    assert_response :success
    assert_select "body", text: /Status sample ingested/, count: 0
  end

  test "Status leads with installs that need a look and the machines behind them" do
    sign_in_as @user
    down = Machine.create!(name: "down", ssh_host: "10.0.0.9", ssh_private_key: "k",
                           status: "unreachable", owner: @project)
    failing = @project.installs.create!(name: "acme-web")
    failing.install_targets.create!(machine: down, status: "failed")
    healthy = @project.installs.create!(name: "acme-ok")
    healthy.install_targets.create!(machine: @observer, status: "running")

    get root_path
    assert_response :success
    # The bad install surfaces through the shared install row; the healthy one stays quiet.
    assert_select ".install-rows a[href=?]", install_path(failing), text: "acme-web"
    assert_select ".install-rows a[href=?]", install_path(healthy), count: 0
    # The unreachable box is called out separately, through the shared machine row.
    assert_select ".machine-rows a[href=?]", machine_path(down), text: "down"
    assert_select ".all-clear", count: 0
  end

  test "the record filters by selector and time, and keeps the query in the form" do
    sign_in_as @user
    Event.record!(actor: "alice", action: "deployed", machine: @observer, summary: "deployed nginx", at: 1.hour.ago)
    Event.record!(actor: "ci", action: "rolled back", at: 40.days.ago)

    get record_path(q: "actor=alice", since: "7d")
    assert_response :success
    assert_select ".filter-bar"
    assert_select "input[name=q][value=?]", "actor=alice"          # query echoed back
    assert_select "select[name=since] option[selected][value=?]", "7d"
    assert_select ".chain-entry", 1                                 # only alice, in window
    assert_select ".result-count", /1 entry/

    get record_path                                                # unfiltered shows both
    assert_select ".chain-entry", 2
  end

  test "machine show reads observe status (cached), without touching the network" do
    sign_in_as @user
    canned = { ok: true, data: { "data" => { "machine" => { "hostname" => "obs.local", "load1" => "0.1" } } }, at: Time.current }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get machine_path(@observer) }
    assert_response :success
    assert_select ".panel.observe", /obs\.local/
    assert_select ".panel.readonly", /observe.*key/i  # observe machine: read-only, not amber
    assert_select ".integrity.ok"                      # the chain-integrity line
  end

  # A POST, not a GET: it opens an SSH connection to the box, and Turbo prefetches
  # links on hover — a read must not be something the pointer can trigger.
  test "refresh re-reads and redirects (observe, changes nothing)" do
    sign_in_as @user
    stub_returning(Steward::Observe, :status, { ok: true, data: {}, at: Time.current }) do
      post refresh_machine_path(@observer)
    end
    assert_redirected_to machine_path(@observer)
  end

  test "refresh is not reachable by GET, so a hover or a prefetch cannot fire it" do
    sign_in_as @user
    get refresh_machine_path(@observer)
    assert_response :not_found
  end

  test "the ceremony previews the exact record line without writing anything" do
    sign_in_as @user
    assert_no_difference -> { Event.count } do
      get new_machine_mutation_path(@operator, act: "apply-updates")
    end
    assert_response :success
    assert_select ".ceremony"
    assert_select ".chain-entry.is-pending .chain-what", /updated op/  # the would-be line
    assert_select "form[action=?]", machine_mutation_path(@operator)           # Confirm POSTs
  end

  test "an unknown or invalid act is refused" do
    sign_in_as @user
    get new_machine_mutation_path(@operator, act: "rm-rf")
    assert_redirected_to machine_path(@operator)
  end

  test "mutate is refused on an observe-only machine and issues nothing" do
    sign_in_as @user
    assert_no_difference -> { Event.count } do
      post machine_mutation_path(@observer, act: "apply-updates")
    end
    assert_redirected_to machine_path(@observer)
    assert_match(/operate/i, flash[:alert])
  end

  test "mutate records the event pending before it runs, then settles it (Invariant 2)" do
    sign_in_as @user
    # Stub only the transport: the Event must be written even though we don't hit SSH.
    stub_returning(Steward, :read, { ok: true, data: { "ok" => true }, at: Time.current }) do
      assert_difference -> { Event.count }, 1 do
        post machine_mutation_path(@operator, act: "apply-updates")
      end
    end
    assert_redirected_to machine_path(@operator)
    event = Event.latest.first
    assert_equal @operator.id, event.machine_id
    assert_equal @user.email_address, event.actor
    assert_equal "updated", event.action
    assert_equal "ok", event.outcome          # settled on the same entry
    assert event.finished_at.present?
  end

  test "a failed command settles the entry failed with the box's reason" do
    sign_in_as @user
    stub_returning(Steward, :read, { ok: false, error: "podman: no such app", at: Time.current }) do
      post machine_mutation_path(@operator, act: "apply-updates")
    end
    event = Event.latest.first
    assert_equal "failed", event.outcome
    assert_equal "podman: no such app", event.detail
    assert_match(/failed/i, flash[:alert])
  end

  test "machine page lists its apps read-only, linking to the install (no act verbs)" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    install = project.installs.create!(name: "globex-api")
    install.install_targets.create!(machine: @operator, status: "running")

    # The card lists what the *box* reports, and attaches our record to it — so the
    # box has to report it.
    apps   = [ { "name" => "globex-api", "image" => "ghcr.io/globex/api@sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" } ]
    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => apps } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows a[href=?]", install_path(install), text: "globex-api"
    assert_select ".app-box-rows a", text: "Globex"    # the project it serves
    # The digest is truncated and copyable; the button carries the *whole* reference.
    assert_select ".digest-chip[data-clipboard-text-value=?]", apps.first["image"]
    assert_select ".digest-chip .digest-text", "@abcdef012345"
    assert_select ".acts-app-verbs", count: 0          # acting on an app happens from its project
    assert_select "a", text: "Re-deploy", count: 0
  end

  # Plan and reality are kept apart: an install we placed here that the box does not
  # report back is a gap, stated and never closed on its own.
  test "a placement the box does not report is named as a gap, not shown as running" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    install = project.installs.create!(name: "ghost-api")
    install.install_targets.create!(machine: @operator, status: "running")

    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => [] } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows .row", count: 0
    assert_select ".panel", /Placed here but not reported running/
    assert_select ".panel a[href=?]", install_path(install), text: "ghost-api"
  end

  # …and the mirror of it: something the box runs that we hold no placement for. A
  # machine-view deploy keeps no Install, so this is a normal state, not an alarm.
  test "an app the box runs with no placement of ours says so" do
    sign_in_as @user
    apps   = [ { "name" => "stray", "image" => "docker.io/stray@sha256:0011223344556677001122334455667700112233445566770011223344556677" } ]
    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => apps } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows .row-name", "stray"
    assert_select ".app-box-rows .badge.unowned", "not in our record"
  end

  test "a lifecycle act targets an app on the machine and records the install" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    app = project.installs.create!(name: "globex-api")
    app.install_targets.create!(machine: @operator, status: "running")
    stub_returning(Steward, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "restart", install_id: app.id)
    end
    event = Event.latest.first
    assert_equal "restarted", event.action
    assert_equal app.id, event.install_id
    assert_equal "ok", event.outcome
  end

  test "deploy composes (a form, no write), then previews the resolved spec" do
    sign_in_as @user
    app = deployable_app

    assert_no_difference -> { Event.count } do
      get new_machine_mutation_path(@operator, act: "deploy", install_id: app.id)
    end
    assert_select "form.compose"
    assert_select "input[name=image]"

    get new_machine_mutation_path(@operator, act: "deploy", install_id: app.id,
          image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e")
    assert_select ".ceremony .spec"
    assert_select ".chain-entry.is-pending .chain-what", /deployed web/
  end

  test "deploy records pending, pipes the envelope, settles ok, and pins desired_image" do
    sign_in_as @user
    app    = deployable_app
    target = app.install_targets.find_by(machine: @operator)

    with_fake_steward do |steward|
      steward.on(/deploy web/, data: { "ok" => true })
      assert_difference -> { Event.count }, 1 do
        post machine_mutation_path(@operator, act: "deploy", install_id: app.id,
              image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e")
      end
      assert_match "@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", steward.stdin_for(/deploy web/), "envelope on stdin"
    end

    event = Event.latest.first
    assert_equal "deployed", event.action
    assert_equal "ok", event.outcome
    assert_equal "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", target.reload.desired_image
  end

  test "rollback issues the parameterless command and records it" do
    sign_in_as @user
    app = deployable_app
    stub_returning(Steward, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "rollback", install_id: app.id)
    end
    assert_equal "rolled back", Event.latest.first.action
  end

  test "remove records the act and retires the target on success" do
    sign_in_as @user
    app    = deployable_app
    target = app.install_targets.find_by(machine: @operator)
    stub_returning(Steward, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "remove", install_id: app.id)
    end
    assert_equal "removed", Event.latest.first.action
    assert_equal "retired", target.reload.status
  end

  private

  # An app with a running target on the operate machine, ready to deploy.
  def deployable_app
    project = Project.create!(name: "Proj-#{SecureRandom.hex(3)}")
    app = project.installs.create!(name: "web", image: "ghcr.io/acme/web@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf",
                                   hostname: "acme.example", port: 8080, health: "/up")
    app.install_targets.create!(machine: @operator, status: "running")
    app
  end

  # Being short and being able to do something about it are different asks: one is a
  # click on the install, the other is "go get a box". The inbox says which.
  test "status calls out installs with a gap that no free box can close" do
    sign_in_as @user
    stuck = @project.installs.create!(name: "stuck", count: 2, exposure: "balanced",
                                      image: "img@sha256:#{'c' * 64}")

    get root_path
    assert_response :success
    # The operate box in the fleet is not this project's, so nothing can take it.
    assert_select ".section-note", /asks for more boxes than are free/
    assert_select ".section-note a", text: "stuck"

    # Give the project a box it may use and the call-out goes away — the gap is still
    # open, but it is now a click, not an errand.
    ProjectMachine.create!(project: @project, machine: @operator.tap { |m| m.update!(owner: @project) })
    get root_path
    assert_select ".section-note", 0
    assert_select ".install-rows a", text: "stuck"   # still listed: still short
  end
end
