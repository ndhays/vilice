require "test_helper"

# The App and Project pages, brought into line with the machine view: no act on a
# box that cannot take one, one state vocabulary, a searchable record, and the
# controls that *configure* an entity behind a click rather than in its title.
class AppProjectPagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @project = Project.create!(name: "Acme")
    @up   = Machine.create!(name: "up-box", ssh_host: "x", scope: "operate",
                            status: "reachable", owner: @project)
    @down = Machine.create!(name: "down-box", ssh_host: "x", scope: "operate",
                            status: "unreachable", owner: @project)
    ProjectMachine.create!(project: @project, machine: @up)
    ProjectMachine.create!(project: @project, machine: @down)
    @app = @project.apps.create!(name: "acme-web", image: "img@sha256:7ae400007ae400007ae400007ae400007ae400007ae400007ae400007ae40000")
  end

  # ── App page ──────────────────────────────────────────────────────────

  # The bug this fixes: every verb travels the same scoped SSH connection, so on an
  # unreachable box all six were certain to fail. The machine page reaches this by not
  # rendering its apps card; the app page lists targets of mixed reachability.
  test "no act is offered for a placement whose box cannot be reached" do
    @app.placements.create!(machine: @down, status: "running")
    get app_path(@app)
    assert_response :success
    assert_select ".acts-app-verbs a", count: 0
    assert_select ".acts-app-verbs", /no act can be issued/
  end

  test "acts are offered for a placement whose box answers" do
    @app.placements.create!(machine: @up, status: "running")
    get app_path(@app)
    assert_select ".acts-app-verbs a", { text: "deploy", count: 1 }
    assert_select ".acts-app-verbs", { text: /no act can be issued/, count: 0 }
  end

  # A row badged its raw status, which knows nothing about the box being down.
  test "a placement row and the app header speak one state vocabulary" do
    @app.placements.create!(machine: @down, status: "running")
    get app_path(@app)
    assert_select "h1 .badge.state-unreachable"
    assert_select ".acts-app .badge.state-unreachable", "unreachable"
    assert_select ".badge.state-running", count: 0
  end

  test "the digest is a copy chip, carrying the whole reference" do
    @app.placements.create!(machine: @up, status: "running",
                                     current_image: "img@sha256:aaaabbbbccccddddaaaabbbbccccddddaaaabbbbccccddddaaaabbbbccccdddd", desired_image: "img@sha256:1111222233334444111122223333444411112222333344441111222233334444")
    get app_path(@app)
    assert_select ".placement-image .digest-chip[data-clipboard-text-value=?]", "img@sha256:aaaabbbbccccddddaaaabbbbccccddddaaaabbbbccccddddaaaabbbbccccdddd"
    assert_select ".placement-image .digest-chip .digest-text", "@aaaabbbbcccc"
    assert_select ".placement-image .digest-chip[data-clipboard-text-value=?]", "img@sha256:1111222233334444111122223333444411112222333344441111222233334444"
    assert_select ".placement-image .drift-word", "drift"
  end

  test "the app record is searchable" do
    Event.record!(actor: "ci", action: "deployed", app: @app, summary: "acme-web on up-box")
    Event.record!(actor: "ci", action: "restarted", app: @app, summary: "acme-web on down-box")
    get app_path(@app, q: "restarted")
    assert_select ".chain-entry", 1
    get app_path(@app, q: "nothing-here")
    assert_select ".empty", /Nothing in this record matches/
  end

  # ── Project page ──────────────────────────────────────────────────────────

  # A verdict, always — the Status page's answer scoped to one client. It says whether
  # this client needs you before it says anything else.
  test "a project with trouble names it, and counts underneath as the proof" do
    @app.placements.create!(machine: @down, status: "running")
    get project_path(@project)
    assert_response :success
    assert_select ".verdict.bad .verdict-head", /1 app needs a look/
    assert_select ".verdict.bad .verdict-head", /1 box unreachable/
    assert_select ".verdict-sub", /1 app/
    assert_select ".verdict-sub", /2 machines/
  end

  test "the verdict agrees with its own count" do
    other = @project.apps.create!(name: "second", image: "img@sha256:8888888888888888888888888888888888888888888888888888888888888888")
    [ @app, other ].each { |i| i.placements.create!(machine: @down, status: "running") }
    get project_path(@project)
    assert_select ".verdict-head", /2 apps need a look/
  end

  test "a healthy project reads as Nothing to report, like Status" do
    @app.placements.create!(machine: @up, status: "running")
    @down.update!(status: "reachable")
    get project_path(@project)
    assert_select ".verdict.ok .verdict-head", "Nothing to report"
    assert_select ".verdict-sub", /all running as asked/
    assert_select ".verdict.bad", count: 0
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
