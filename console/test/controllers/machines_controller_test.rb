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
    assert_equal "added machine", Event.latest.first.action
    assert_redirected_to machine_path(machine)
  end

  test "creating a machine from a project links it and returns to the install" do
    sign_in_as @user
    project = Project.create!(name: "Acme")
    assert_difference [ -> { Machine.count }, -> { ProjectMachine.count } ], 1 do
      post machines_path, params: { project_id: project.id, machine: {
        ssh_host: "5.78.9.9", ssh_port: 22, scope: "operate"
      } }
    end
    assert_includes project.machines, Machine.find_by(ssh_host: "5.78.9.9")
    assert_redirected_to new_install_path(project_id: project)
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
      assert_select ".integrity.off"        # box record unreachable
    end
  end

  test "an operate box shows its maintenance window and, when updates pend, Apply Now" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "upd-box", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-updates", value: "3")
      get machine_path(box)
      assert_response :success
      assert_select ".maint-line", /Maintenance — daily at 04:00/
      assert_select ".maint-pending", /3 updates pending/
      assert_select ".acts a", /Apply Now/
    end
  end

  test "an operate box with no updates shows the window and Up to date, no act" do
    with_fake_observe do
      sign_in_as @user
      box = Machine.create!(name: "current-box", ssh_host: "x", scope: "operate")
      box.labels.create!(key: "fake-health", value: "ok") # ok band → 0 updates
      get machine_path(box)
      assert_response :success
      assert_select ".maint-line", /Maintenance — daily at/
      assert_select ".updates-current"
      assert_select ".acts a", { text: /Apply Now/, count: 0 }
    end
  end

  test "the machine page offers an honest Remove with the revoke line" do
    sign_in_as @user
    m = Machine.create!(name: "edge-rm", ssh_host: "x", scope: "operate")
    get machine_path(m)
    assert_response :success
    assert_select ".danger-remove pre.cmd", /steward revoke console/
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
    assert_equal "removed machine", Event.latest.first.action
  end

  test "removing a machine that still runs installs is refused, naming the apps" do
    sign_in_as @user
    project = Project.create!(name: "Acme-rm")
    m = Machine.create!(name: "edge-inst", ssh_host: "x", scope: "operate", owner: project)
    ProjectMachine.create!(project: project, machine: m)
    install = project.installs.create!(name: "web-rm", image: "img@sha256:x")
    install.install_targets.create!(machine: m, status: "running")

    assert_no_difference [ -> { Machine.count }, -> { InstallTarget.count }, -> { Event.count } ] do
      delete machine_path(m)
    end
    assert_redirected_to machine_path(m)
    assert_match(/web-rm/, flash[:alert])
  end

  test "removing a machine with only retired installs keeps the record intact" do
    sign_in_as @user
    project = Project.create!(name: "Acme-retired")
    m = Machine.create!(name: "edge-retired", ssh_host: "x", scope: "operate", owner: project)
    ProjectMachine.create!(project: project, machine: m)
    install = project.installs.create!(name: "web-old", image: "img@sha256:x")
    install.install_targets.create!(machine: m, status: "retired")

    assert_no_difference -> { Install.count } do          # the install survives
      assert_difference -> { InstallTarget.count }, -1 do # its retired target on this box drops
        delete machine_path(m)
      end
    end
    assert install.reload.persisted?
    # The removal event survives with no machine link (events nullify on destroy).
    assert_equal "removed machine", Event.latest.first.action
  end

  # ── Index search + unowned filter ──────────────────────────────────────────
  test "index searches by name and filters to unowned with a presence count" do
    sign_in_as @user
    owner = Project.create!(name: "Acme-idx")
    Machine.create!(name: "web-alpha", ssh_host: "x", owner: owner)
    Machine.create!(name: "db-beta",   ssh_host: "x", owner: owner)
    Machine.create!(name: "free-gamma", ssh_host: "x") # unowned

    get machines_path(q: "alpha")
    assert_response :success
    assert_select ".rows .row-name", text: "web-alpha"
    assert_select ".rows .row-name", text: "db-beta", count: 0

    get machines_path(unowned: "1")
    assert_select ".rows .row-name", text: "free-gamma"
    assert_select ".rows .row-name", text: "web-alpha", count: 0
    assert_select ".action-chips .chip.on"
    assert_select ".action-chips .chip .chip-count", text: "1"
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
    assert_equal "set sharing", Event.latest.first.action
  end

  test "transfer reassigns the owner, and release leaves it unowned — both recorded" do
    sign_in_as @user
    a = Project.create!(name: "A-xfer")
    b = Project.create!(name: "B-xfer")
    m = Machine.create!(name: "xfer-box", ssh_host: "x", owner: a)

    patch transfer_machine_path(m), params: { machine: { owner_id: b.id } }
    assert_equal b, m.reload.owner
    assert_equal "transferred machine", Event.latest.first.action

    patch transfer_machine_path(m), params: { machine: { owner_id: "" } }
    assert m.reload.unowned?
    assert_equal "released machine", Event.latest.first.action
  end

  private

  def with_fake_observe
    ENV["STEWARD_FAKE_OBSERVE"] = "1"
    yield
  ensure
    ENV.delete("STEWARD_FAKE_OBSERVE")
  end
  # ── The machine view is pack-shaped ──────────────────────────────────────
  # Sections exist because the box reports the pack, not because we assumed it.

  def packs_reply(packs)
    { ok: true, at: Time.current,
      data: { "data" => { "manifest" => "/etc/steward/packs.manifest", "packs" => packs } } }
  end

  test "a box reports which packs may run on it" do
    sign_in_as @user
    machine = Machine.create!(name: "packed", ssh_host: "10.0.0.9", scope: "observe")
    reply = packs_reply([ { "name" => "steward-app", "state" => "active", "digest" => "sha256:abc" } ])
    stub_observe(packs: reply) { get machine_path(machine) }
    assert_response :success
    assert_select ".panel.observe", /steward-app/
  end

  test "a box with no packs says it runs the core and nothing else" do
    sign_in_as @user
    machine = Machine.create!(name: "bare", ssh_host: "10.0.0.10", scope: "observe")
    stub_observe(packs: packs_reply([])) { get machine_path(machine) }
    assert_response :success
    assert_match(/core and nothing else/, response.body)
    assert_match(/cannot deploy/, response.body)
  end

  # The note matters more than the flag: "stale" alone looks like tampering until you
  # can see that an upgrade skipped prepare.
  test "a pack that cannot run surfaces why" do
    sign_in_as @user
    machine = Machine.create!(name: "stale-box", ssh_host: "10.0.0.11", scope: "observe")
    reply = packs_reply([ { "name" => "steward-app", "state" => "stale",
                            "note" => "authorized at a different digest — re-run `steward prepare`" } ])
    stub_observe(packs: reply) { get machine_path(machine) }
    assert_response :success
    assert_match(/stale/, response.body)
    assert_match(/re-run/, response.body)
  end

  # The dangerous misreading is an empty list meaning "this box runs nothing".
  test "an unreachable box reports what runs there as unknown, not none" do
    sign_in_as @user
    machine = Machine.create!(name: "gone-box2", ssh_host: "10.0.0.12", scope: "observe")
    stub_observe(packs: { ok: false, error: "connection refused" }) { get machine_path(machine) }
    assert_response :success
    assert_match(/unknown, not none/, response.body)
    assert_no_match(/core and nothing else/, response.body)
  end
end
