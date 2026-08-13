require "test_helper"

# An install is a placement: pick an app (+ its latest version) or, when the library-only
# setting is off, a custom image — and a box to put it on. A project is optional context
# carried in the URL (decisions/console-layers.md); with one, the machine list narrows to
# that project's boxes. (decisions/open/app-library.md)
class InstallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user     = users(:one)
    @project  = Project.create!(name: "Acme")
    @app      = App.create!(name: "web", port: 8080, health: "/up")
    @version  = @app.versions.create!(tag: "v1", image: "ghcr.io/acme/web@sha256:abc")
    @app.set_latest!(@version)
    @operator = Machine.create!(name: "op", ssh_host: "10.0.0.4", scope: "operate", ssh_private_key: "k", owner: @project)
    ProjectMachine.create!(project: @project, machine: @operator)
  end

  test "the install form is behind the login" do
    get new_install_path(project_id: @project)
    assert_redirected_to new_session_path
  end

  test "new lists installable apps + the project's machines, and has no project field" do
    sign_in_as @user
    get new_install_path(project_id: @project)
    assert_response :success
    assert_select "h1", /Create New Install for Acme/
    assert_select "input[type=radio][name=?]", "install[app_id]"  # the catalog picker
    assert_select "input[name='install[app_id]'][checked]", false # nothing pre-selected
    assert_select "select[name=?]", "install[version_id]"         # version (default latest)
    assert_select "select[name=?]", "install[machine_id]"
    assert_select "select[name=?]", "install[project_id]", false  # project is the context
    assert_select "textarea[name=?]", "install[volumes]"          # the Storage step
  end

  # The inversion (decisions/console-layers.md): tenancy is the outermost, optional
  # ring, so the form must stand up with no project anywhere — and it still must not
  # ask for one, since a project is context in the URL, never a dropdown.
  test "new works with no project, offering every operate box in the fleet" do
    sign_in_as @user
    Machine.create!(name: "loose", ssh_host: "10.0.0.8", scope: "operate", ssh_private_key: "k")
    Machine.create!(name: "eyes",  ssh_host: "10.0.0.9", scope: "observe", ssh_private_key: "k")

    get new_install_path
    assert_response :success
    assert_select "h1", /\ACreate New Install\z/
    assert_select "select[name=?]", "install[project_id]", false
    # The unowned box and the project's box are both offered; the observe-only one isn't.
    assert_select "select[name='install[machine_id]'] option", text: "loose"
    assert_select "select[name='install[machine_id]'] option", text: "op"
    assert_select "select[name='install[machine_id]'] option", { text: "eyes", count: 0 }
  end

  # The acceptance test for the inversion: an app placed on a box with no client invented
  # to hold it. Straight through to the same witnessed deploy ceremony.
  test "create places an install with no project and hands off to the deploy ceremony" do
    sign_in_as @user
    loose = Machine.create!(name: "loose", ssh_host: "10.0.0.8", scope: "operate", ssh_private_key: "k")

    assert_difference [ -> { Install.count }, -> { InstallTarget.count }, -> { Event.count } ], 1 do
      post installs_path, params: { install: {
        app_id: @app.id, machine_id: loose.id, hostname: "home.example"
      } }
    end
    install = Install.last
    assert_nil install.project_id
    assert_equal loose, install.install_targets.sole.machine
    assert_equal "web on loose", Event.latest.first.summary   # no client in the line
    assert_redirected_to new_machine_mutation_path(loose, act: "deploy", install_id: install.id)
  end

  test "the fleet-wide install list carries projectless placements" do
    sign_in_as @user
    mine  = @project.installs.create!(name: "web", image: "img@sha256:abc")
    loose = Install.create!(name: "pihole", image: "img@sha256:def")

    get installs_path
    assert_response :success
    assert_select ".install-rows a[href=?]", install_path(mine),  text: "web"
    assert_select ".install-rows a[href=?]", install_path(loose), text: "pihole"
    # Whose work it is, where there's an answer — and a plain dash where there isn't.
    assert_select ".cell-project a", text: "Acme"
  end

  test "new leads with placement — single/fleet, then existing/new box" do
    sign_in_as @user
    get new_install_path(project_id: @project)
    assert_response :success
    # Placement is the first step (machine moved to the top).
    assert_select "fieldset.placement legend", /Machine Configuration/i
    assert_select ".placement input[type=radio][name=placement][value=?]", "single"
    assert_select ".placement input[type=radio][name=placement][value=?]", "fleet"
    assert_select ".placement input[name=machine_source][value=?]", "existing"
    assert_select ".placement input[name=machine_source][value=?]", "new"
    # Fleet is no longer a stub: exposure is a real choice and the count it gates is the
    # real intention. What's still previewed is the new-box path, and the fact that the
    # console doesn't manage the balancer an app can be marked as sitting behind.
    assert_select ".placement input[type=radio][name=?][value=?]", "install[exposure]", "edge"
    assert_select ".placement input[type=radio][name=?][value=?]", "install[exposure]", "balanced"
    assert_select ".placement input[type=number][name=?]", "install[count]"
    # The balancer is real now too — a picker, not a note about something unbuilt. The
    # new-box (Hetzner) path is the only previewed stub left in this step.
    assert_select ".placement .balanced-only"
    assert_select ".placement .stub-note", 1
    assert_select ".placement .stub-note", { text: /coming soon/i, count: 1 }   # new box
  end

  test "create installs the app's latest version, then hands off to the deploy ceremony" do
    sign_in_as @user
    assert_difference [ -> { Install.count }, -> { InstallTarget.count }, -> { Event.count } ], 1 do
      post installs_path(project_id: @project), params: { install: {
        app_id: @app.id, machine_id: @operator.id, hostname: "acme.example"
      } }
    end
    install = Install.last
    assert_equal @project.id, install.project_id
    assert_equal @app.id, install.app_id
    assert_equal @version.id, install.version_id        # latest
    assert_equal @version.image, install.image
    assert_equal "web", install.name                    # defaulted from the app
    assert_equal "added", Event.latest.first.action
    assert_redirected_to new_machine_mutation_path(@operator, act: "deploy", install_id: install.id)
  end

  test "create can pin a specific version (the default is latest)" do
    sign_in_as @user
    v2 = @app.versions.create!(tag: "v2", image: "ghcr.io/acme/web@sha256:def")  # @version (v1) stays latest
    post installs_path(project_id: @project), params: { install: {
      app_id: @app.id, version_id: v2.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last
    assert_equal v2.id, install.version_id
    assert_equal v2.image, install.image
  end

  # The Storage textarea is one `source:/path` per line; blank lines are dropped and the
  # rest land in `config.volumes`, which `deploy_envelope` carries to the box.
  test "create parses the volumes textarea into the install config" do
    sign_in_as @user
    post installs_path(project_id: @project), params: { install: {
      app_id: @app.id, machine_id: @operator.id, hostname: "acme.example",
      volumes: "storage:/rails/storage\n\n/srv/x:/data:ro\n"
    } }
    install = Install.last
    assert_equal [ "storage:/rails/storage", "/srv/x:/data:ro" ], install.volumes
    assert_equal [ "storage:/rails/storage", "/srv/x:/data:ro" ],
                 install.deploy_envelope(image: @version.image).dig(:app, :volumes)
  end

  # A malformed mount fails the install like a bad name/port — before the act, whole
  # transaction rolled back.
  test "a malformed volume is refused" do
    sign_in_as @user
    assert_no_difference [ -> { Install.count }, -> { InstallTarget.count } ] do
      post installs_path(project_id: @project), params: { install: {
        app_id: @app.id, machine_id: @operator.id, hostname: "acme.example",
        volumes: "storage"   # no container path
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a machine not on the project is rejected" do
    sign_in_as @user
    stray = Machine.create!(name: "stray", ssh_host: "10.0.0.9", scope: "operate")
    assert_no_difference -> { Install.count } do
      post installs_path(project_id: @project), params: { install: {
        app_id: @app.id, machine_id: stray.id, hostname: "x"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a custom image is refused while library-only, allowed when off" do
    sign_in_as @user
    params = { install: { image: "ghcr.io/x@sha256:z", machine_id: @operator.id, hostname: "x", name: "raw" } }

    assert_no_difference -> { Install.count } do
      post installs_path(project_id: @project), params: params   # library-only (default)
    end
    assert_response :unprocessable_entity

    Setting.current.update!(installs_library_only: false)
    assert_difference -> { Install.count }, 1 do
      post installs_path(project_id: @project), params: params
    end
    install = Install.last
    assert_nil install.app_id
    assert_equal "ghcr.io/x@sha256:z", install.image
  end

  # The Install is the app-actions home (decisions/install-the-app-actions-home.md).
  test "show renders the install — state, the box it runs on, and the witnessed verbs" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", app: @app, version: @version,
                                        image: @version.image, hostname: "acme.example")
    install.install_targets.create!(machine: @operator, status: "running",
                                    desired_image: @version.image, current_image: @version.image)

    get install_path(install)
    assert_response :success
    assert_select "h1", /web/
    assert_select ".badge.state-running"
    assert_select ".acts-app-name a", /op/                     # the box it runs on
    assert_select ".acts-app-verbs a", text: "Re-deploy"       # verbs live here too
    # the verb returns to the install page, not the machine
    assert_select "a[href=?]",
      new_machine_mutation_path(@operator, act: "deploy", install_id: install.id, from: "install")
  end

  test "show lists the install's declared volumes" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", app: @app, version: @version,
                                        image: @version.image, config: { "volumes" => [ "storage:/rails/storage" ] })
    install.install_targets.create!(machine: @operator, status: "running")

    get install_path(install)
    assert_response :success
    assert_select ".addr .mono", /storage:\/rails\/storage/
  end

  # The ceremony is keyed to a machine, but `from: install` returns to the install page.
  test "an act launched from the install page returns there" do
    sign_in_as @user
    observer = Machine.create!(name: "obs", ssh_host: "10.0.0.7", scope: "observe", ssh_private_key: "k", owner: @project)
    ProjectMachine.create!(project: @project, machine: observer)
    install = @project.installs.create!(name: "web", app: @app, version: @version, image: @version.image)
    install.install_targets.create!(machine: observer, status: "pending")

    # observe scope can't act — the guard redirect proves the return path is the install
    post machine_mutation_path(observer, act: "restart", install_id: install.id, from: "install")
    assert_redirected_to install_path(install)
  end

  # Isolation #4 — a name already running on a shared box (from another project) blocks
  # the install and rolls back the whole transaction.
  test "an install name already on the shared box is refused" do
    sign_in_as @user
    @operator.update!(sharing: "everyone")
    other = Project.create!(name: "Other")
    ProjectMachine.create!(project: other, machine: @operator)
    other.installs.create!(name: "web", image: "img@sha256:abc")
         .install_targets.create!(machine: @operator)

    assert_no_difference [ -> { Install.count }, -> { InstallTarget.count }, -> { Event.count } ] do
      post installs_path(project_id: @project), params: { install: {
        app_id: @app.id, machine_id: @operator.id, hostname: "acme.example"  # app name "web" collides
      } }
    end
    assert_response :unprocessable_entity
  end

  # ── Restating the intention (decisions/drift-is-surfaced-never-closed.md) ─────

  test "edit reaches the intention and not the spec" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abc")

    get edit_install_path(install)
    assert_response :success
    assert_select "input[name=?][value=?]", "install[exposure]", "balanced"
    assert_select "input[type=number][name=?]", "install[count]"
    # The spec is not editable here — a different concern, and not what this act records.
    assert_select "input[name=?]", "install[image]", false
    assert_select "input[name=?]", "install[name]", false
    assert_select "textarea[name=?]", "install[volumes]", false
  end

  test "restating the intention records the act and moves the gap" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abc")
    install.install_targets.create!(machine: @operator, status: "running")
    @operator.update!(status: "reachable")
    assert install.reload.in_step?

    assert_difference -> { Event.count }, 1 do
      patch install_path(install), params: { install: { count: 3, exposure: "balanced" } }
    end
    assert_redirected_to install_path(install)

    install.reload
    assert_equal 3, install.count
    assert install.exposure_balanced?
    assert_equal(-2, install.placement_gap, "asking for more opens a gap")

    event = Event.latest.first
    assert_equal "restated", event.action
    assert_equal "web: asked for 1 box, edge → 3 boxes, balanced", event.summary
    assert_nil event.outcome, "a control-plane act with no box has nothing to settle"
  end

  # The corollary that matters most: a changed number is not a destructive call.
  test "asking for fewer boxes removes nothing" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abc",
                                        count: 3, exposure: "balanced")
    install.install_targets.create!(machine: @operator, status: "running")

    assert_no_difference [ -> { InstallTarget.count },
                           -> { InstallTarget.where(status: "retired").count } ] do
      patch install_path(install), params: { install: { count: 1, exposure: "edge" } }
    end
    assert_equal 1, install.reload.count
    assert_equal "running", install.install_targets.sole.status,
                 "the app is still on the box — removing it is a separate, witnessed act"
  end

  test "an intention the exposure can't deliver is refused" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abc")

    assert_no_difference -> { Event.count } do
      patch install_path(install), params: { install: { count: 4, exposure: "edge" } }
    end
    assert_response :unprocessable_entity
    assert_equal 1, install.reload.count
  end

  test "restating nothing records nothing" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abc")

    assert_no_difference -> { Event.count } do
      patch install_path(install), params: { install: { count: 1, exposure: "edge" } }
    end
  end

  # The constraint the inversion leans on: uniqueness lives on the box, so it holds
  # across the project boundary in both directions — including for a placement that has
  # no project to be scoped by.
  test "a projectless install collides with a project's install on the same box" do
    sign_in_as @user
    @project.installs.create!(name: "web", image: "img@sha256:abc")
            .install_targets.create!(machine: @operator)

    assert_no_difference [ -> { Install.count }, -> { InstallTarget.count } ] do
      post installs_path, params: { install: {
        app_id: @app.id, machine_id: @operator.id, hostname: "home.example"
      } }
    end
    assert_response :unprocessable_entity
  end
end
