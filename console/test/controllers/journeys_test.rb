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
  # The App and Project pages did not, so a routine sample could take a slot on
  # the one page that is meant to show what *happened* to that app.
  test "a status sample never reaches the App or Project record either" do
    sign_in_as @user
    app = @project.apps.create!(name: "chain-app")
    Event.record!(actor: "alice", action: "deployed", machine: @observer,
                  project: @project, app: app, summary: "chain-app on obs")
    Event.record!(actor: "snapshot.timer", action: "observed", machine: @observer,
                  project: @project, app: app, summary: "Status sample ingested")

    get app_path(app)
    assert_response :success
    assert_select ".chain-entry", 1
    assert_select "body", text: /Status sample ingested/, count: 0

    get project_path(@project)
    assert_response :success
    assert_select "body", text: /Status sample ingested/, count: 0
  end

  test "Status leads with apps that need a look and the machines behind them" do
    sign_in_as @user
    down = Machine.create!(name: "down", ssh_host: "10.0.0.9", ssh_private_key: "k",
                           status: "unreachable", owner: @project)
    failing = @project.apps.create!(name: "acme-web")
    failing.placements.create!(machine: down, status: "failed")
    healthy = @project.apps.create!(name: "acme-ok")
    healthy.placements.create!(machine: @observer, status: "running")

    get root_path
    assert_response :success
    # The bad app surfaces through the shared app row; the healthy one stays quiet.
    assert_select ".app-rows a[href=?]", app_path(failing), text: "acme-web"
    assert_select ".app-rows a[href=?]", app_path(healthy), count: 0
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
    stub_observe(status: canned, record: record) { get live_machine_path(@observer) }
    assert_response :success
    assert_select ".panel.observe", /obs\.local/
    assert_select ".panel.readonly", /observe.*key/i  # observe machine: read-only, not amber
    assert_select ".integrity.ok"                      # the chain-integrity line
  end

  # A POST, not a GET: it opens an SSH connection to the box, and Turbo prefetches
  # links on hover — a read must not be something the pointer can trigger.
  test "refresh re-reads and redirects (observe, changes nothing)" do
    sign_in_as @user
    stub_returning(Vilice::Observe, :status, { ok: true, data: {}, at: Time.current }) do
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
    assert_select ".chain-entry.is-pending .chain-what", /apply-updates op/  # the would-be line
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
    stub_returning(Vilice, :read, { ok: true, data: { "ok" => true }, at: Time.current }) do
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
    # The box's reply is kept on the entry; the command recorded before it ran is not
    # touched by settling.
    assert_equal({ "ok" => true }, event.output)
    assert_equal "apply-updates --json", event.raw["command"]
  end

  test "a failed command settles the entry failed with the box's reason" do
    sign_in_as @user
    stub_returning(Vilice, :read, { ok: false, error: "podman: no such app", at: Time.current }) do
      post machine_mutation_path(@operator, act: "apply-updates")
    end
    event = Event.latest.first
    assert_equal "failed", event.outcome
    assert_equal "podman: no such app", event.detail
    assert_equal "podman: no such app", event.output  # no raw reply, so the reason stands in
    assert_match(/failed/i, flash[:alert])
  end

  test "machine page lists its apps read-only, linking to the app (no act verbs)" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    app = project.apps.create!(name: "globex-api")
    app.placements.create!(machine: @operator, status: "running")

    # The card lists what the *box* reports, and attaches our record to it — so the
    # box has to report it.
    apps   = [ { "name" => "globex-api", "image" => "ghcr.io/globex/api@sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789" } ]
    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => apps } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get live_machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows a[href=?]", app_path(app), text: "globex-api"
    assert_select ".app-box-rows a", text: "Globex"    # the project it serves
    # The digest is truncated and copyable; the button carries the *whole* reference.
    assert_select ".digest-chip[data-clipboard-text-value=?]", apps.first["image"]
    assert_select ".digest-chip .digest-text", "@abcdef012345"
    assert_select ".acts-app-verbs", count: 0          # acting on an app happens from its project
    assert_select "a[href*=?]", "act=deploy", count: 0  # no app redeploy here
  end

  # Plan and reality are kept apart: an app we placed here that the box does not
  # report back is a gap, stated and never closed on its own.
  test "a placement the box does not report is named as a gap, not shown as running" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    app = project.apps.create!(name: "ghost-api")
    app.placements.create!(machine: @operator, status: "running")

    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => [] } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get live_machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows .row", count: 0
    assert_select ".panel", /Placed here but not reported running/
    assert_select ".panel a[href=?]", app_path(app), text: "ghost-api"
  end

  # …and the mirror of it: something the box runs that we hold no placement for. A
  # machine-view deploy keeps no App, so this is a normal state, not an alarm.
  test "an app the box runs with no placement of ours says so" do
    sign_in_as @user
    apps   = [ { "name" => "stray", "image" => "docker.io/stray@sha256:0011223344556677001122334455667700112233445566770011223344556677" } ]
    canned = { ok: true, at: Time.current,
               data: { "data" => { "machine" => { "hostname" => "op.local" }, "apps" => apps } } }
    record = { ok: true, data: { "data" => { "entries" => [], "count" => 0, "intact" => true } }, at: Time.current }
    stub_observe(status: canned, record: record) { get live_machine_path(@operator) }
    assert_response :success
    assert_select ".app-box-rows .row-name", "stray"
    assert_select ".app-box-rows .badge.unowned", "not in our record"
  end

  test "a lifecycle act targets an app on the machine and records the app" do
    sign_in_as @user
    project = Project.create!(name: "Globex")
    app = project.apps.create!(name: "globex-api")
    app.placements.create!(machine: @operator, status: "running")
    stub_returning(Vilice, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "restart", app_id: app.id)
    end
    event = Event.latest.first
    assert_equal "restarted", event.action
    assert_equal app.id, event.app_id
    assert_equal "ok", event.outcome
  end

  test "deploy composes (a form, no write), then previews the resolved spec" do
    sign_in_as @user
    app = deployable_app

    assert_no_difference -> { Event.count } do
      get new_machine_mutation_path(@operator, act: "deploy", app_id: app.id)
    end
    assert_select "form.compose"
    assert_select "input[name=image]"

    get new_machine_mutation_path(@operator, act: "deploy", app_id: app.id,
          image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e")
    assert_select ".ceremony .spec"
    assert_select ".chain-entry.is-pending .chain-what", /deploy web on op/
  end

  test "deploy records pending, pipes the envelope, settles ok, and pins desired_image" do
    sign_in_as @user
    app    = deployable_app
    placement = app.placements.find_by(machine: @operator)

    with_fake_vilice do |vilice|
      vilice.on(/deploy web/, data: { "ok" => true })
      assert_difference -> { Event.count }, 1 do
        post machine_mutation_path(@operator, act: "deploy", app_id: app.id,
              image: "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e")
      end
      assert_match "@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", vilice.stdin_for(/deploy web/), "envelope on stdin"
    end

    event = Event.latest.first
    assert_equal "deployed", event.action
    assert_equal "ok", event.outcome
    assert_equal "ghcr.io/acme/web@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e", placement.reload.desired_image
  end

  test "rollback issues the parameterless command and records it" do
    sign_in_as @user
    app = deployable_app
    stub_returning(Vilice, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "rollback", app_id: app.id)
    end
    assert_equal "rolled back", Event.latest.first.action
  end

  test "remove records the act and retires the placement on success" do
    sign_in_as @user
    app    = deployable_app
    placement = app.placements.find_by(machine: @operator)
    stub_returning(Vilice, :read, { ok: true, data: {}, at: Time.current }) do
      post machine_mutation_path(@operator, act: "remove", app_id: app.id)
    end
    assert_equal "removed", Event.latest.first.action
    assert_equal "retired", placement.reload.status
  end

  private

  # An app with a running target on the operate machine, ready to deploy.
  def deployable_app
    project = Project.create!(name: "Proj-#{SecureRandom.hex(3)}")
    app = project.apps.create!(name: "web", image: "ghcr.io/acme/web@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf",
                                   hostname: "acme.example", port: 8080, health: "/up")
    app.placements.create!(machine: @operator, status: "running")
    app
  end

  # Being short and being able to do something about it are different asks: one is a
  # click on the app, the other is "go get a box". The inbox says which.
  test "status calls out apps with a gap that no free box can close" do
    sign_in_as @user
    stuck = @project.apps.create!(name: "stuck", count: 2, exposure: "balanced",
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
    assert_select ".app-rows a", text: "stuck"   # still listed: still short
  end

  # ── The authorize gap, at the last place it can bite ───────────────────────
  # A box that never ran its authorize line refuses the key, and ssh says "Permission
  # denied (publickey)" — which reads as though the console did something wrong. The
  # act is still recorded and still failed; what changes is that the alert names the
  # fix (decisions/open/what-could-go-wrong.md).
  test "an act that never reached the box names the authorize gap, and is still recorded" do
    sign_in_as @user
    assert_nil @operator.last_seen_at, "the fixture box has never answered — the case under test"

    with_fake_vilice do |vilice|
      vilice.on(/apply-updates/, stdout: "Permission denied (publickey).",
                 success: false, exit_status: 255)
      assert_difference -> { Event.count }, 1 do
        post machine_mutation_path(@operator, act: "apply-updates")
      end
    end

    # Record before act still holds: we tried, so it is written, and it settled failed.
    assert_equal "failed", Event.latest.first.outcome
    assert_match(/never answered Vilice/, flash[:alert])
    assert_match(/authorize line/, flash[:alert])
  end

  # The other half of the same coin: a box that answered and refused the act is a
  # different problem, and must not be told to go run an authorize line.
  test "an act the box refused keeps the box's own reason and adds no connection advice" do
    sign_in_as @user

    with_fake_vilice do |vilice|
      vilice.on(/apply-updates/, stdout: "podman: no such app", success: false)  # exit 1, reached
      post machine_mutation_path(@operator, act: "apply-updates")
    end

    assert_match(/podman: no such app/, flash[:alert])
    assert_no_match(/authorize line/, flash[:alert])
  end

  # A box we reached before and have lost has a different fix again — and the
  # provider's own firewall is the one that catches people out.
  test "a box that answered before and does not now points at the firewall, not the key" do
    sign_in_as @user
    @operator.update!(last_seen_at: 1.hour.ago, status: "unreachable")

    with_fake_vilice do |vilice|
      vilice.on(/apply-updates/, stdout: "Connection timed out", success: false, exit_status: 255)
      post machine_mutation_path(@operator, act: "apply-updates")
    end

    assert_match(/answered before/, flash[:alert])
    assert_match(/firewall/, flash[:alert])
    assert_no_match(/authorize line/, flash[:alert])
  end

  # Said before the press as well as after the failure — but a warning, never a block.
  # A box authorized a minute ago has not been observed yet and reads exactly like this.
  test "the ceremony warns about an unauthorized box without disabling Confirm" do
    sign_in_as @user
    # A real box always carries one: the keypair is generated when the machine is added.
    @operator.update!(ssh_public_key: "ssh-ed25519 AAAAC3Nz console@op")

    get new_machine_mutation_path(@operator, act: "apply-updates")
    assert_response :success

    assert_select ".ceremony-warn", /never answered Vilice/
    assert_select ".ceremony-warn .cmd", /vilice authorize/
    assert_select "form[action=?]", machine_mutation_path(@operator)   # still pressable

    # Once the box has answered, the caution has no reason to be there.
    @operator.update!(last_seen_at: Time.current, status: "reachable")
    get new_machine_mutation_path(@operator, act: "apply-updates")
    assert_select ".ceremony-warn", 0
  end
end
