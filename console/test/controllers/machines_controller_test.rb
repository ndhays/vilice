require "test_helper"

# Onboarding (Add Machine): register a box, generate Steward Console's scoped keypair,
# and surface the authorize line (decisions/open/machine-onboarding.md).
class MachinesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "the add-machine form is behind the login" do
    get new_machine_path
    assert_redirected_to new_session_path
  end

  test "new renders the form (no SSH user field — always steward)" do
    sign_in_as @user
    get new_machine_path
    assert_response :success
    assert_select "h1", /Add Machine/
    assert_select "input[name=?]", "machine[name]", false # name mirrors the box, not typed
    assert_select "input[name=?]", "machine[ssh_user]", false # not a form choice
    # Scope is a vertical radio-card group (observe / operate), not a dropdown.
    assert_select "select[name=?]", "machine[scope]", false
    assert_select ".radio-cards input[type=radio][name=?][value=?]", "machine[scope]", "observe"
    assert_select ".radio-cards input[type=radio][name=?][value=?]", "machine[scope]", "operate"
  end

  # This form is the reference shape every other stack-form follows
  # (blueprint/console/interface.md, "The form pattern"). Pinned here because a
  # vocabulary nothing checks is a vocabulary that drifts back apart — which is how
  # this form and apps/new came to disagree in the first place.
  test "the reference form: steps with legends, errors at the top, the act's glyph" do
    sign_in_as @user
    get new_machine_path
    assert_response :success

    # Every field lives in a step, and every step says what it is for.
    assert_select "form.stack-form fieldset.step", 3
    assert_select "form.stack-form fieldset.step > legend", 3
    assert_select "fieldset.step > legend", /Address/i
    assert_select "fieldset.step > legend", /Scope/i
    assert_select "fieldset.step > legend", /Owner/i
    # Nothing is a bare field hanging outside a step.
    assert_select "form.stack-form > .field", 0

    # Address leads. Tenancy is optional context and comes last — the same order
    # apps/new takes, which never asks you to settle a client first.
    legends = css_select("fieldset.step > legend").map { |l| l.text.strip[/\A\w+/] }
    assert_equal %w[Address Scope Owner], legends

    # Hints stay where the label cannot carry the choice: Operate and Grant are not
    # tellable apart from one word. The placement cards have none, and that is the rule.
    assert_select ".radio-cards .radio-hint", 3

    # The submit wears the act's glyph — `added machine`, and `added` draws a plus.
    assert_select ".form-actions button svg.icon", 1
  end

  test "errors render above the first step, not after the field that failed" do
    sign_in_as @user
    post machines_path, params: { machine: { ssh_host: "", ssh_port: 22, scope: "operate" } }
    assert_response :unprocessable_entity

    # The error is the reason you are back on this page, so it comes before the form's
    # first question rather than buried between two of them.
    assert_select "form.stack-form > *:first-child.flash.alert"
  end

  test "new without a project offers an optional owner dropdown (Unassigned first)" do
    sign_in_as @user
    Project.create!(name: "Acme-pick")
    get new_machine_path
    assert_response :success
    assert_select "select[name=?]", "machine[owner_id]"
    assert_select "option[value=?]", "", text: "Unassigned"
  end

  test "create assigns an owner picked from the dropdown (no project in the URL)" do
    sign_in_as @user
    project = Project.create!(name: "Acme-assign")
    assert_difference -> { Machine.count }, 1 do
      post machines_path, params: { machine: {
        ssh_host: "10.5.5.5", ssh_port: 22, scope: "operate", owner_id: project.id
      } }
    end
    machine = Machine.find_by(ssh_host: "10.5.5.5")
    assert_equal project, machine.owner
    assert_redirected_to machine_path(machine)
  end

  test "create generates a scoped keypair, records it, and redirects" do
    sign_in_as @user
    assert_difference [ -> { Machine.count }, -> { Event.count } ], 1 do
      post machines_path, params: { machine: {
        ssh_host: "5.78.1.1", ssh_port: 22, scope: "operate"
      } }
    end
    machine = Machine.find_by(ssh_host: "5.78.1.1")
    assert_equal "5.78.1.1", machine.name               # seeded from the host until the first read
    assert_equal "steward", machine.ssh_user            # forced, not a form choice
    assert machine.ssh_private_key.present?, "private key generated + stored"
    assert_match(/\Assh-ed25519 /, machine.ssh_public_key)
    assert_equal "added", Event.latest.first.action
    assert_redirected_to machine_path(machine)
  end

  test "creating a machine from a project links it and returns to the app" do
    sign_in_as @user
    project = Project.create!(name: "Acme")
    assert_difference [ -> { Machine.count }, -> { ProjectMachine.count } ], 1 do
      post machines_path, params: { project_id: project.id, machine: {
        ssh_host: "5.78.9.9", ssh_port: 22, scope: "operate"
      } }
    end
    assert_includes project.machines, Machine.find_by(ssh_host: "5.78.9.9")
    assert_redirected_to new_app_path(project_id: project)
  end

  test "an invalid machine re-renders and generates nothing" do
    sign_in_as @user
    assert_no_difference -> { Machine.count } do
      post machines_path, params: { machine: { name: "", ssh_host: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "the machine page surfaces the authorize line" do
    sign_in_as @user
    machine = Machine.create!(name: "edge-2", ssh_host: "5.78.1.2", scope: "operate",
                              ssh_public_key: "ssh-ed25519 AAAAKEY console@edge-2")
    offline = { ok: false, error: "unreachable", at: Time.current }
    stub_observe(status: offline, record: offline) { get machine_path(machine) }
    assert_response :success
    assert_select ".access pre.cmd", /steward authorize .* --client console --scope operate/
    assert_select ".access .cmd-block .cmd-copy[aria-label=?]", "Copy command"
  end

  # End-to-end through a real request: with the fake-observe seam on, the machine
  # page renders live health straight from the `fake-health` label — no stub, no
  # box, no network. This is what the seeded scenarios rely on.
  test "fake-observe renders a critical box from its label" do
    with_fake_observe do
      sign_in_as @user
      crit = Machine.create!(name: "crit-box", ssh_host: "x", scope: "observe")
      crit.labels.create!(key: "fake-health", value: "crit")
      get machine_path(crit)
      assert_response :success
      assert_select ".health-line.crit"     # loud health line
      assert_select ".integrity.ok"         # box record reads back intact
    end
  end

  test "fake-observe renders an offline box as unreachable" do
    with_fake_observe do
      sign_in_as @user
      gone = Machine.create!(name: "gone-box", ssh_host: "x", scope: "observe")
      gone.labels.create!(key: "fake-health", value: "offline")
      get machine_path(gone)
      assert_response :success
      assert_select ".integrity.bad", /Box record unavailable/   # red: old news, not absent
    end
  end

  test "an operate box shows its maintenance window, and Operate offers Apply updates with its command" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "upd-box", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-updates", value: "3")
      get machine_path(box)
      assert_response :success
      # Observe reports; it holds no act.
      assert_select ".zone-observe .kicker", "Maintenance"
      assert_select ".maint-line", /Daily at 04:00/
      assert_select ".maint-pending", /3 updates waiting/
      assert_select ".zone-observe .act", count: 0
      assert_select ".zone-observe a[href*=?]", "act=apply-updates", count: 0
      # Operate offers it, on a button named for the command it sends.
      assert_select ".zone-operate .act", /3 OS updates waiting/ do
        assert_select "a.btn.cmd[href=?]", new_machine_mutation_path(box, act: "apply-updates"), text: "apply-updates"
      end
      # The ceremony opens inside the zone that writes.
      assert_select ".zone-operate turbo-frame#ceremony"
    end
  end

  test "an operate box with no updates shows the window and Up to date, no act" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "current-box", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-health", value: "ok") # ok band → 0 updates
      get machine_path(box)
      assert_response :success
      assert_select ".maint-line", /Daily at/
      assert_select ".updates-current"
      # The act still shows its command — the page is a reference too — but offers no button.
      assert_select ".zone-operate .act", /up to date/ do
        assert_select ".btn.cmd[aria-disabled=true]", "apply-updates"
        assert_select "a", count: 0
      end
    end
  end

  # Settings configure the box; they do not report on it. They sit apart and closed,
  # so reaching a destructive control takes a deliberate click.
  test "machine settings are a closed section, not part of the page's body" do
    sign_in_as @user
    m = Machine.create!(name: "edge-set", ssh_host: "x", scope: "operate")
    get machine_path(m)
    assert_response :success
    assert_select "details.page-settings > summary", /Machine Settings/
    assert_select "details.page-settings[open]", count: 0
    # The controls are inside it, not loose on the page.
    assert_select "details.page-settings .access-panel"
    assert_select "details.page-settings .panel.danger-remove"
    # Removing is a panel, not a second disclosure: the section is already the gate,
    # and two nested <details> read as one pattern repeated rather than two things.
    assert_select "details.danger-remove", count: 0
  end

  test "the machine page offers an honest Remove with the revoke line" do
    sign_in_as @user
    m = Machine.create!(name: "edge-rm", ssh_host: "x", scope: "operate")
    get machine_path(m)
    assert_response :success
    assert_select ".danger-remove pre.cmd", /steward revoke console/
    # Every command shown is meant to be pasted into a shell, so none has to be
    # selected by hand — the button copies the exact text shown.
    assert_select ".danger-remove .cmd-block .cmd-copy[data-clipboard-text-value=?]",
                  "steward revoke console"
    assert_select ".danger-remove form[action=?]", machine_path(m)
  end

  test "removing a machine records it and redirects to the fleet" do
    sign_in_as @user
    m = Machine.create!(name: "edge-gone", ssh_host: "x", scope: "operate")
    assert_difference [ -> { Machine.count } ], -1 do
      assert_difference -> { Event.count }, 1 do
        delete machine_path(m)
      end
    end
    assert_redirected_to machines_path
    assert_equal "removed", Event.latest.first.action
  end

  test "removing a machine that still runs apps is refused, naming the apps" do
    sign_in_as @user
    project = Project.create!(name: "Acme-rm")
    m = Machine.create!(name: "edge-inst", ssh_host: "x", scope: "operate", owner: project)
    ProjectMachine.create!(project: project, machine: m)
    app = project.apps.create!(name: "web-rm", image: "img@sha256:8888888888888888888888888888888888888888888888888888888888888888")
    app.placements.create!(machine: m, status: "running")

    assert_no_difference [ -> { Machine.count }, -> { Placement.count }, -> { Event.count } ] do
      delete machine_path(m)
    end
    assert_redirected_to machine_path(m)
    assert_match(/web-rm/, flash[:alert])
  end

  test "removing a machine with only retired apps keeps the record intact" do
    sign_in_as @user
    project = Project.create!(name: "Acme-retired")
    m = Machine.create!(name: "edge-retired", ssh_host: "x", scope: "operate", owner: project)
    ProjectMachine.create!(project: project, machine: m)
    app = project.apps.create!(name: "web-old", image: "img@sha256:8888888888888888888888888888888888888888888888888888888888888888")
    app.placements.create!(machine: m, status: "retired")

    assert_no_difference -> { App.count } do          # the app survives
      assert_difference -> { Placement.count }, -1 do # its retired placement on this box drops
        delete machine_path(m)
      end
    end
    assert app.reload.persisted?
    # The removal event survives with no machine link (events nullify on destroy).
    assert_equal "removed", Event.latest.first.action
  end

  # ── Index search + grouping ────────────────────────────────────────────────
  test "index searches by name" do
    sign_in_as @user
    owner = Project.create!(name: "Acme-idx")
    Machine.create!(name: "web-alpha", ssh_host: "x", owner: owner)
    Machine.create!(name: "db-beta",   ssh_host: "x", owner: owner)

    get machines_path(q: "alpha")
    assert_response :success
    assert_select ".rows .row-name", text: "web-alpha"
    assert_select ".rows .row-name", text: "db-beta", count: 0
  end

  # Grouping replaced the old "unowned" filter: it showed one answer at a time,
  # where the grouping shows every answer at once, with counts.
  test "grouping by project heads each group and gathers the boxes with no home" do
    sign_in_as @user
    owner = Project.create!(name: "Acme-idx")
    Machine.create!(name: "web-alpha", ssh_host: "x", owner: owner)
    Machine.create!(name: "free-gamma", ssh_host: "x") # unowned

    get machines_path(group: "project")
    assert_response :success
    # Both are on the page — a grouping narrows nothing.
    assert_select ".rows .row-name", text: "web-alpha"
    assert_select ".rows .row-name", text: "free-gamma"
    # "No project" leads, because a box with no home is the one that needs a look.
    assert_select ".group-head:first-of-type .group-name", text: "No project"
    assert_select ".group-head .group-name", text: "Acme-idx"
    assert_select ".action-chips .chip.on", text: /Project/
  end

  test "grouping by reachability leads with the boxes that cannot be reached" do
    sign_in_as @user
    Machine.create!(name: "up-1",   ssh_host: "x", status: "reachable")
    Machine.create!(name: "down-1", ssh_host: "x", status: "unreachable")

    get machines_path(group: "status")
    assert_response :success
    assert_select ".group-head:first-of-type .group-name", text: "Unreachable"
  end

  # The headline states this ring's facts and no others.
  test "the headline counts boxes, unreachable, and never-seen" do
    sign_in_as @user
    Machine.create!(name: "down-2", ssh_host: "x", status: "unreachable")
    Machine.create!(name: "new-2",  ssh_host: "x") # status defaults to unknown

    get machines_path
    assert_response :success
    assert_select ".headline .bad", text: /1 unreachable/
    assert_select ".headline .muted", text: /1 not yet seen/
  end

  # A grouping has its own URL, so the view can be shared — the rule the Record
  # destination already follows. A stale one degrades to the default view.
  test "an unknown grouping falls back to reachability rather than erroring" do
    sign_in_as @user
    Machine.create!(name: "solo-1", ssh_host: "x")
    get machines_path(group: "no-such-grouping")
    assert_response :success
    assert_select ".rows .row-name", text: "solo-1"
    assert_select ".group-head .group-name", text: "Not yet seen"
  end

  # The page opens grouped, without being asked.
  test "the fleet is grouped by reachability by default" do
    sign_in_as @user
    Machine.create!(name: "down-9", ssh_host: "x", status: "unreachable")
    get machines_path
    assert_response :success
    assert_select ".group-head .group-name", text: "Unreachable"
    assert_select ".action-chips .chip.on", text: /Reachability/
  end

  # An icon that carries meaning explains itself on hover *and* on keyboard focus,
  # and is labelled for a screen reader — a native title does none of that.
  test "row icons carry a focusable, labelled tooltip" do
    sign_in_as @user
    Machine.create!(name: "tip-1", ssh_host: "x", status: "reachable", balancer: true)
    get machines_path
    assert_response :success
    assert_select ".status-ico.hint[data-tip=?][tabindex=?]", "Reachable", "0"
    assert_select ".role-ico.hint[data-tip=?]", "Load Balancer — 0 hosts"
    assert_select ".scope-ico.hint[aria-label*=?]", "OBSERVE"
  end

  # The fleet view draws the edge relationship instead of describing it: the
  # balancer heads its group, the boxes it fronts are marked as sitting behind it.
  test "the fleet view marks the balancer and the hosts behind it" do
    sign_in_as @user
    project = Project.create!(name: "Tree-idx")
    edge    = Machine.create!(name: "aaa-edge", ssh_host: "x", scope: "operate", balancer: true)
    host    = Machine.create!(name: "zzz-host", ssh_host: "x")
    loose   = Machine.create!(name: "mmm-loose", ssh_host: "x")
    app = project.apps.create!(name: "app-tree", image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                       exposure: "balanced", balancer: edge)
    app.placements.create!(machine: host, status: "running")

    get machines_path(group: "fleet")
    assert_response :success
    assert_select ".rows.fleet-rows .row.is-edge .row-name", text: "aaa-edge"
    assert_select ".rows.fleet-rows .row.is-behind .row-name", text: "zzz-host"
    # A box under no balancer gets a plain list — there is no edge to sit under.
    assert_select ".row.is-behind .row-name", text: "mmm-loose", count: 0
    # The tree already draws the edge here, so the row does not also spell it out.
    assert_select ".rows.fleet-rows .row.is-behind .behind-edge", count: 0

    # Under any *other* grouping the relationship can't be drawn — a group of
    # unreachable boxes is not a fleet — so the row names its edge instead. It is a
    # fact about the one box, which is why it survives the change of grouping.
    get machines_path(group: "status")
    assert_response :success
    assert_select ".row", text: /zzz-host/ do
      assert_select ".behind-edge a[href=?]", machine_path(edge), text: "aaa-edge"
    end
    # The edge itself is behind nothing, and neither is a box with no balancer.
    assert_select ".behind-edge", 1
  end

  # The trailing glyph says what the box carries, not just what kind it is.
  test "the role tooltip counts apps on a host and hosts behind a balancer" do
    sign_in_as @user
    project = Project.create!(name: "Roles-idx")
    host    = Machine.create!(name: "host-idx", ssh_host: "x")
    edge    = Machine.create!(name: "edge-idx", ssh_host: "x", scope: "operate", balancer: true)
    app = project.apps.create!(name: "app-idx", image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                       exposure: "balanced", balancer: edge)
    app.placements.create!(machine: host, status: "running")
    Machine.create!(name: "bare-idx", ssh_host: "x") # carries nothing

    get machines_path
    assert_response :success
    assert_select ".role-ico.hint[data-tip=?]", "Host — 1 app"
    assert_select ".role-ico.hint[data-tip=?]", "Load Balancer — 1 host"
    # A box carrying nothing says so plainly rather than claiming a count of zero.
    assert_select ".role-ico.hint[data-tip=?]", "Host"
  end

  # ── Ownership & sharing (machine-ownership.md) ─────────────────────────────
  test "registering a machine from a project makes that project the owner" do
    sign_in_as @user
    project = Project.create!(name: "Acme-own")
    assert_difference -> { Machine.count }, 1 do
      post machines_path(project_id: project.id),
           params: { machine: { ssh_host: "10.9.9.9", ssh_port: 22, scope: "operate" } }
    end
    assert_equal project, Machine.find_by(ssh_host: "10.9.9.9").owner
  end

  test "sharing mode is set and recorded" do
    sign_in_as @user
    m = Machine.create!(name: "share-me", ssh_host: "x", owner: Project.create!(name: "O1"))
    assert_difference -> { Event.count }, 1 do
      patch sharing_machine_path(m), params: { machine: { sharing: "everyone" } }
    end
    assert m.reload.sharing_everyone?
    assert_equal "set", Event.latest.first.action
  end

  test "transfer reassigns the owner, and release leaves it unowned — both recorded" do
    sign_in_as @user
    a = Project.create!(name: "A-xfer")
    b = Project.create!(name: "B-xfer")
    m = Machine.create!(name: "xfer-box", ssh_host: "x", owner: a)

    patch transfer_machine_path(m), params: { machine: { owner_id: b.id } }
    assert_equal b, m.reload.owner
    assert_equal "transferred", Event.latest.first.action

    patch transfer_machine_path(m), params: { machine: { owner_id: "" } }
    assert m.reload.unowned?
    assert_equal "released", Event.latest.first.action
  end

  private

  # ── The status cards: backups, certificates, the record, and who can reach it ──
  test "a box under pressure shows an app never backed up and a cert close to expiry" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "cards-box", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-health", value: "warn")
      app = App.create!(name: "shop", hostname: "shop.example")
      app.placements.create!(machine: box, status: "running")
      get machine_path(box)
      assert_response :success

      assert_select ".zone-observe .panel", /Backups/ do
        assert_select ".fact-rows li.warn", /shop.*Never backed up/m
        assert_select ".fact-rows li.ok", /The record.*Backed up/m
      end
      assert_select ".zone-observe .panel", /Certificates/ do
        assert_select ".fact-rows li.warn", /shop\.example.*Expires in \d+ days/m
      end
      assert_select ".zone-observe .panel .kicker", "Record"
      # The fake answers no `actors` read, and an unread ledger is never shown empty.
      assert_select ".keyholders", /Could not read the ledger/
      assert_select ".keyholders .access-rows", count: 0
    end
  end

  test "a failing backup and an expired cert read as failures, with the reason" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "crit-cards", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-health", value: "crit")
      app = App.create!(name: "shop2", hostname: "shop2.example")
      app.placements.create!(machine: box, status: "running")
      get machine_path(box)
      assert_select ".fact-rows li.bad", /Last attempt failed/
      assert_select ".fact-rows li.bad .fact-detail", /connection refused/
      assert_select ".fact-rows li.bad", /Not trusted · expired/
    end
  end

  test "a box with no backup repo says nothing on it is backed up" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "no-repo", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-backups", value: "off")
      get machine_path(box)
      assert_select ".card-verdict.bad", /Nothing on this box is backed up/
    end
  end

  def with_fake_observe
    ENV["STEWARD_FAKE_OBSERVE"] = "1"
    yield
  ensure
    ENV.delete("STEWARD_FAKE_OBSERVE")
  end
  # ── The machine view is shaped by the box's role ─────────────────────────
  # Sections exist because the box says what it is for, not because we assumed.

  def status_reply(role)
    { ok: true, at: Time.current,
      data: { "data" => { "machine" => { "hostname" => "box" }, "role" => role } } }
  end

  test "a box reports what it was prepared as" do
    sign_in_as @user
    machine = Machine.create!(name: "app-box", ssh_host: "10.0.0.9", scope: "observe")
    stub_observe(status: status_reply("host")) { get machine_path(machine) }
    assert_response :success
    assert_select ".panel.observe", /host/
  end

  # A balancer has no container runtime and would refuse a deploy by name, so the
  # Apps section is absent rather than empty.
  test "a balancer shows no apps section" do
    sign_in_as @user
    machine = Machine.create!(name: "edge-box", ssh_host: "10.0.0.11", scope: "observe")
    stub_observe(status: status_reply("balancer")) { get machine_path(machine) }
    assert_response :success
    assert_select ".kicker", { text: "Apps on this box", count: 0 }
  end

  # A box that has never been prepared has no role to report. That reads as unknown,
  # never as a claim that it can do nothing.
  test "an unprepared box reads as not prepared, not as running nothing" do
    sign_in_as @user
    machine = Machine.create!(name: "fresh-box", ssh_host: "10.0.0.10", scope: "observe")
    stub_observe(status: status_reply("")) { get machine_path(machine) }
    assert_response :success
    assert_select ".facts dd", "not prepared"
    assert_select "h1 .health-line", /Online/
    assert_select ".kicker", "Apps on this box"
  end

  # The dangerous misreading is an unreachable box looking like an empty one. It is
  # prevented structurally now rather than by a sentence: the cards that could only
  # have held a live read are *absent*, so nothing is left to be read as "none".
  test "an unreachable box shows no live-read card at all, so none can read as empty" do
    sign_in_as @user
    machine = Machine.create!(name: "gone-box2", ssh_host: "10.0.0.12", scope: "observe")
    stub_observe(status: { ok: false, error: "connection refused" }) { get machine_path(machine) }
    assert_response :success
    # One card owns the message.
    assert_select ".panel.unreachable", /could not reach/
    # Nothing anywhere claims the box runs nothing, or is healthy, or is hardened.
    assert_select ".app-box-rows", count: 0
    assert_select "body", text: /No apps on this box/, count: 0
    assert_select ".metrics", count: 0
    assert_select ".hardening-line", count: 0
    # Every act travels the same connection that just failed, so none is offered.
    assert_select ".zone-operate .act", count: 0
    # …but re-reading is exactly what you want to do next.
    assert_select ".panel.unreachable form[action=?]", refresh_machine_path(machine)
  end
end
