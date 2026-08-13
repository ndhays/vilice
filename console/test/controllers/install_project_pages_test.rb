require "test_helper"

# The Install and Project pages, brought into line with the machine view: no act on a
# box that cannot take one, one state vocabulary, a searchable record, and the
# controls that *configure* an entity behind a click rather than in its title.
class InstallProjectPagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @project = Project.create!(name: "Acme")
    @up   = Machine.create!(name: "up-box", ssh_host: "x", scope: "operate",
                            status: "reachable", owner: @project)
    @down = Machine.create!(name: "down-box", ssh_host: "x", scope: "operate",
                            status: "unreachable", owner: @project)
    ProjectMachine.create!(project: @project, machine: @up)
    ProjectMachine.create!(project: @project, machine: @down)
    @install = @project.installs.create!(name: "acme-web", image: "img@sha256:want0000")
  end

  # ── Install page ──────────────────────────────────────────────────────────

  # The bug this fixes: every verb travels the same scoped SSH connection, so on an
  # unreachable box all six were certain to fail. The machine page reaches this by not
  # rendering its apps card; the install page lists targets of mixed reachability.
  test "no act is offered for a target whose box cannot be reached" do
    @install.install_targets.create!(machine: @down, status: "running")
    get install_path(@install)
    assert_response :success
    assert_select ".acts-app-verbs a", count: 0
    assert_select ".acts-app-verbs", /no act can be issued/
  end

  test "acts are offered for a target whose box answers" do
    @install.install_targets.create!(machine: @up, status: "running")
    get install_path(@install)
    assert_select ".acts-app-verbs a", { text: "Re-deploy", count: 1 }
    assert_select ".acts-app-verbs", { text: /no act can be issued/, count: 0 }
  end

  # A row badged its raw status, which knows nothing about the box being down.
  test "a target row and the install header speak one state vocabulary" do
    @install.install_targets.create!(machine: @down, status: "running")
    get install_path(@install)
    assert_select "h1 .badge.state-unreachable"
    assert_select ".acts-app .badge.state-unreachable", "unreachable"
    assert_select ".badge.state-running", count: 0
  end

  test "the digest is a copy chip, carrying the whole reference" do
    @install.install_targets.create!(machine: @up, status: "running",
                                     current_image: "img@sha256:aaaabbbbccccdddd", desired_image: "img@sha256:1111222233334444")
    get install_path(@install)
    assert_select ".target-image .digest-chip[data-clipboard-text-value=?]", "img@sha256:aaaabbbbccccdddd"
    assert_select ".target-image .digest-chip .digest-text", "@aaaabbbbcccc"
    assert_select ".target-image .digest-chip[data-clipboard-text-value=?]", "img@sha256:1111222233334444"
    assert_select ".target-image .drift-word", "drift"
  end

  test "the install record is searchable" do
    Event.record!(actor: "ci", action: "deployed", install: @install, summary: "acme-web on up-box")
    Event.record!(actor: "ci", action: "restarted", install: @install, summary: "acme-web on down-box")
    get install_path(@install, q: "restarted")
    assert_select ".chain-entry", 1
    get install_path(@install, q: "nothing-here")
    assert_select ".empty", /Nothing in this record matches/
  end

  # ── Project page ──────────────────────────────────────────────────────────

  # The headline answers "does my client have a problem" without scanning three lists.
  test "the project leads with a headline of its own ring's facts" do
    @install.install_targets.create!(machine: @down, status: "running")
    get project_path(@project)
    assert_response :success
    assert_select ".headline", /1 install/
    assert_select ".headline", /2 machines/
    assert_select ".headline .bad", /1 need a look/
    assert_select ".headline .bad", /1 unreachable/
  end

  test "a healthy project says so in the same line" do
    @install.install_targets.create!(machine: @up, status: "running")
    @down.update!(status: "reachable")
    get project_path(@project)
    assert_select ".headline .ok", /all running as asked/
  end

  # A destructive control does not belong in a page title.
  test "delete moves out of the title into a closed settings section" do
    get project_path(@project)
    assert_response :success
    assert_select "h1 form[action=?]", project_path(@project), count: 0
    assert_select "h1 .star-btn"                       # the focus lens stays
    assert_select "details.page-settings > summary", /Project Settings/
    assert_select "details.page-settings[open]", count: 0
    assert_select "details.page-settings .danger-remove form[action=?]", project_path(@project)
  end

  # A section that can only ever say "None" on most projects is noise.
  test "the shared-machines section is absent when nothing is shared" do
    get project_path(@project)
    assert_select "h2", { text: "Shared Machines", count: 0 }
  end

  test "the project record is searchable" do
    Event.record!(actor: "alice", action: "added", project: @project, summary: "Acme")
    Event.record!(actor: "bob", action: "edited", project: @project, summary: "Acme")
    get project_path(@project, q: "edited")
    assert_select ".chain-entry", 1
  end
end
