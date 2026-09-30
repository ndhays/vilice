require "test_helper"

# An install is a placement: pick an app (+ its latest version) or, when the library-only
# setting is off, a custom image — and a box to put it on. A project is optional context
# carried in the URL (decisions/console-layers.md); with one, the machine list narrows to
# that project's boxes. (decisions/open/app-library.md)
class InstallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user     = users(:one)
    @project  = Project.create!(name: "Acme")
    @app_template      = AppTemplate.create!(name: "web", port: 8080, health: "/up")
    @version  = @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/web@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    @app_template.set_latest!(@version)
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
    # One name for one thing — the crumb carries the project, the heading does not.
    assert_select "h1", /\AAdd App\z/
    assert_select ".breadcrumb", /Acme/
    assert_select "input[type=radio][name=?]", "install[app_template_id]"  # the catalog picker
    assert_select "input[name='install[app_template_id]'][checked]", false # nothing pre-selected
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
    assert_select "h1", /\AAdd App\z/
    assert_select "select[name=?]", "install[project_id]", false
    # The unowned box and the project's box are both offered; the observe-only one isn't.
    # Neither has ever answered us, so both carry the authorize gap on the option itself
    # rather than letting you find it out when the SSH call fails.
    assert_select "select[name='install[machine_id]'] option", text: "loose — not yet authorized"
    assert_select "select[name='install[machine_id]'] option", text: "op — not yet authorized"
    assert_select "select[name='install[machine_id]'] option", { text: /eyes/, count: 0 }
    # And "no box" is a real option, not the absence of one.
    assert_select "select[name='install[machine_id]'] option", text: /place it later/
  end

  # A box is optional because an install is an intention, and an intention does not need
  # one (decisions/drift-is-surfaced-never-closed.md). What comes back is an install that
  # states what should run and shows the gap it just opened.
  test "create with no box states the intention and opens the gap" do
    sign_in_as @user

    assert_difference [ -> { Install.count }, -> { Event.count } ], 1 do
      assert_no_difference -> { InstallTarget.count } do
        post installs_path(project_id: @project), params: { install: {
          app_template_id: @app_template.id, hostname: "acme.example", count: 2, exposure: "balanced"
        } }
      end
    end

    install = Install.last
    assert_redirected_to install_path(install)
    assert_equal "unplaced", install.state          # no targets, and the model knew this word
    assert_equal(-2, install.placement_gap)         # asked for two, serving none
    # One act, and it names no machine: nothing was placed and nothing was deployed.
    act = Event.latest.first
    assert_equal "added", act.action
    assert_nil act.machine_id
  end

  # A blank box is a legitimate answer; a box this install may not land on is not. The
  # second must not be quietly turned into the first.
  test "create refuses a box outside the project instead of silently dropping it" do
    sign_in_as @user
    outsider = Machine.create!(name: "outsider", ssh_host: "10.0.0.7", scope: "operate",
                               ssh_private_key: "k")

    assert_no_difference [ -> { Install.count }, -> { Event.count } ] do
      post installs_path(project_id: @project), params: { install: {
        app_template_id: @app_template.id, machine_id: outsider.id, hostname: "acme.example"
      } }
    end
    assert_response :unprocessable_entity
    assert_match(/pick another, or leave it blank and place it later/, response.body)
  end

  # The acceptance test for the inversion: an app placed on a box with no client invented
  # to hold it. Straight through to the same witnessed deploy ceremony.
  test "create places an install with no project and hands off to the deploy ceremony" do
    sign_in_as @user
    loose = Machine.create!(name: "loose", ssh_host: "10.0.0.8", scope: "operate", ssh_private_key: "k")

    # Two decisions, so two acts: stating what should run, and landing it on a box.
    assert_difference [ -> { Install.count }, -> { InstallTarget.count } ], 1 do
      assert_difference -> { Event.count }, 2 do
        post installs_path, params: { install: {
          app_template_id: @app_template.id, machine_id: loose.id, hostname: "home.example"
        } }
      end
    end
    install = Install.last
    assert_nil install.project_id
    assert_equal loose, install.install_targets.sole.machine
    placed, added = Event.latest.first(2)
    assert_equal %w[placed added], [ placed.action, added.action ]
    assert_equal "web on loose", placed.summary   # no client in the line
    assert_equal "web", added.summary             # the intention names no box
    assert_redirected_to new_machine_mutation_path(loose, act: "deploy", install_id: install.id)
  end

  test "the fleet-wide install list carries projectless placements" do
    sign_in_as @user
    mine  = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    loose = Install.create!(name: "pihole", image: "img@sha256:defdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefd")

    get installs_path
    assert_response :success
    assert_select ".install-rows a[href=?]", install_path(mine),  text: "web"
    assert_select ".install-rows a[href=?]", install_path(loose), text: "pihole"
    # Whose work it is, where there's an answer — and a plain dash where there isn't.
    assert_select ".cell-project a", text: "Acme"
  end

  test "new leads with placement — single or fleet, and the box is its own optional step" do
    sign_in_as @user
    get new_install_path(project_id: @project)
    assert_response :success
    # Scale is the first step. It was "Machine Configuration" — jargon for a plain idea,
    # and untrue once the box moved to its own step.
    assert_select "fieldset.placement > legend", /\AScale/
    assert_select ".placement input[type=radio][name=placement][value=?]", "single"
    assert_select ".placement input[type=radio][name=placement][value=?]", "fleet"
    # Both card pairs in this step — placement and exposure — are label-only. The whole
    # choice is the two words; a sentence under each was restating them.
    assert_select ".placement .radio-cards:not(.plain)", 0
    assert_select ".placement .radio-hint", 0
    assert_select ".placement > .radio-cards.plain .radio", 2
    # Provisioning a box from here is not offered at all while it is an open question
    # (decisions/open/create-machine.md) — no source radios, and no stub in the built path.
    assert_select ".placement input[name=machine_source]", 0
    # The box is not inside the placement step any more, and not inside a Single-only
    # reveal: it is optional in both branches, which is what lets Fleet submit at all.
    assert_select ".placement select[name=?]", "install[machine_id]", false
    assert_select ".single-only", 0
    assert_select "fieldset.step > legend", /First box/i
    assert_select "select[name=?]", "install[machine_id]"
    # So the submit no longer disappears on the Fleet branch, and no longer promises a
    # deploy it only sometimes does. It wears the act's name and the act's glyph.
    assert_select ".form-actions button", /Add App\z/
    assert_select ".form-actions button svg.icon", 1
    assert_select ".stub-note", 0
    # Fleet: exposure is a real choice and the count it gates is the real intention, and
    # the balancer is a real picker.
    assert_select ".placement input[type=radio][name=?][value=?]", "install[exposure]", "edge"
    assert_select ".placement input[type=radio][name=?][value=?]", "install[exposure]", "balanced"
    assert_select ".placement input[type=number][name=?]", "install[count]"
    assert_select ".placement .balanced-only"
  end

  # The second form to follow the reference shape (blueprint/console/interface.md, "The
  # form pattern"). Add Machine sets it; this one is the same vocabulary with more in it,
  # so the legends are checked here too — plain words, one concern each, no bare fields.
  test "the install form follows the reference shape Add Machine sets" do
    sign_in_as @user
    get new_install_path(project_id: @project)
    assert_response :success

    legends = css_select("form.stack-form fieldset.step > legend").map { |l| l.text.strip[/\A[\w ]+/].strip }
    assert_equal [ "Scale", "First box", "Template", "Hostname", "Template defaults", "Storage" ], legends
    # Nothing outside a step, including inside the progressive-reveal wrapper.
    assert_select "form.stack-form > .field", 0
    assert_select "form.stack-form > [data-install-form-target=rest] > .field", 0
  end

  test "create installs the app's latest version, then hands off to the deploy ceremony" do
    sign_in_as @user
    assert_difference [ -> { Install.count }, -> { InstallTarget.count } ], 1 do
      assert_difference -> { Event.count }, 2 do
        post installs_path(project_id: @project), params: { install: {
          app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
        } }
      end
    end
    install = Install.last
    assert_equal @project.id, install.project_id
    assert_equal @app_template.id, install.app_template_id
    assert_equal @version.id, install.version_id        # latest
    assert_equal @version.image, install.image
    assert_equal "web", install.name                    # defaulted from the app
    assert_equal %w[placed added], Event.latest.first(2).map(&:action)
    assert_redirected_to new_machine_mutation_path(@operator, act: "deploy", install_id: install.id)
  end

  test "create can pin a specific version (the default is latest)" do
    sign_in_as @user
    v2 = @app_template.versions.create!(tag: "v2", image: "ghcr.io/acme/web@sha256:defdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefdefd")  # @version (v1) stays latest
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, version_id: v2.id, machine_id: @operator.id, hostname: "acme.example"
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
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example",
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
        app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example",
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
        app_template_id: @app_template.id, machine_id: stray.id, hostname: "x"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a custom image is refused while library-only, allowed when off" do
    sign_in_as @user
    params = { install: { image: "ghcr.io/x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", machine_id: @operator.id, hostname: "x", name: "raw" } }

    assert_no_difference -> { Install.count } do
      post installs_path(project_id: @project), params: params   # library-only (default)
    end
    assert_response :unprocessable_entity

    Setting.current.update!(installs_library_only: false)
    assert_difference -> { Install.count }, 1 do
      post installs_path(project_id: @project), params: params
    end
    install = Install.last
    assert_nil install.app_template_id
    assert_equal "ghcr.io/x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", install.image
  end

  # The Install is the app-actions home (decisions/install-the-app-actions-home.md).
  test "show renders the install — state, the box it runs on, and the witnessed verbs" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", app_template: @app_template, version: @version,
                                        image: @version.image, hostname: "acme.example")
    install.install_targets.create!(machine: @operator, status: "running",
                                    desired_image: @version.image, current_image: @version.image)

    get install_path(install)
    assert_response :success
    assert_select "h1", /web/
    assert_select ".badge.state-running"
    assert_select ".acts-app-name a", /op/                     # the box it runs on
    assert_select ".acts-app-verbs a", text: "deploy"       # verbs live here too
    # the verb returns to the install page, not the machine
    assert_select "a[href=?]",
      new_machine_mutation_path(@operator, act: "deploy", install_id: install.id, from: "install")
  end

  test "show lists the install's declared volumes" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", app_template: @app_template, version: @version,
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
    install = @project.installs.create!(name: "web", app_template: @app_template, version: @version, image: @version.image)
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
    other.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
         .install_targets.create!(machine: @operator)

    assert_no_difference [ -> { Install.count }, -> { InstallTarget.count }, -> { Event.count } ] do
      post installs_path(project_id: @project), params: { install: {
        app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"  # app name "web" collides
      } }
    end
    assert_response :unprocessable_entity
  end

  # ── Restating the intention (decisions/drift-is-surfaced-never-closed.md) ─────

  test "edit reaches the intention and not the spec" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")

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
    install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
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
    install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca",
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
    install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")

    assert_no_difference -> { Event.count } do
      patch install_path(install), params: { install: { count: 4, exposure: "edge" } }
    end
    assert_response :unprocessable_entity
    assert_equal 1, install.reload.count
  end

  test "restating nothing records nothing" do
    sign_in_as @user
    install = @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")

    assert_no_difference -> { Event.count } do
      patch install_path(install), params: { install: { count: 1, exposure: "edge" } }
    end
  end

  # The constraint the inversion leans on: uniqueness lives on the box, so it holds
  # across the project boundary in both directions — including for a placement that has
  # no project to be scoped by.
  test "a projectless install collides with a project's install on the same box" do
    sign_in_as @user
    @project.installs.create!(name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
            .install_targets.create!(machine: @operator)

    assert_no_difference [ -> { Install.count }, -> { InstallTarget.count } ] do
      post installs_path, params: { install: {
        app_template_id: @app_template.id, machine_id: @operator.id, hostname: "home.example"
      } }
    end
    assert_response :unprocessable_entity
  end

  # ── The release command reaches the box ────────────────────────────────────
  # Copied from the App at create rather than read at deploy time, so editing the
  # library later never silently changes what an already-placed app runs.
  test "an install copies the app's release command, and a later library edit does not follow" do
    sign_in_as @user
    @app_template.update!(release: [ "bin/rails", "db:migrate" ])

    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last
    assert_equal [ "bin/rails", "db:migrate" ], install.release

    @app_template.update!(release: [ "bin/rails", "db:seed" ])
    assert_equal [ "bin/rails", "db:migrate" ], install.reload.release
  end

  # It has to arrive as a list. A string would be a shell command, and the box has no
  # shell to run it with.
  test "the deploy envelope carries the release command as argv" do
    sign_in_as @user
    @app_template.update!(release: [ "bin/rails", "db:migrate" ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }

    envelope = Install.last.deploy_envelope(image: "img@sha256:#{'a' * 64}")

    assert_equal [ "bin/rails", "db:migrate" ], envelope[:app][:release]
    assert_kind_of Array, envelope[:app][:release]
  end

  test "an app with no release command puts no release key in the envelope" do
    sign_in_as @user
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }

    envelope = Install.last.deploy_envelope(image: "img@sha256:#{'a' * 64}")
    assert_not envelope[:app].key?(:release)
  end

  # The ceremony's job is showing you what you are about to authorize. A command that
  # runs on the box with this app's secrets belongs there, before the press.
  test "the deploy ceremony shows the release command before you confirm it" do
    sign_in_as @user
    @app_template.update!(release: [ "bin/rails", "db:migrate" ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    get new_machine_mutation_path(@operator, act: "deploy", install_id: install.id,
                                  image: install.image, hostname: install.hostname)

    assert_select ".spec", /release/
    assert_select ".spec dd", "bin/rails db:migrate"
    assert_select ".ceremony .note", /nothing is deployed/i
  end

  # ── Accessories reach the box ──────────────────────────────────────────────
  test "an install copies the app's accessories and carries them in the envelope" do
    sign_in_as @user
    db = { "name" => "db", "image" => "postgres@sha256:#{'b' * 64}",
           "volumes" => [ "db-data:/var/lib/postgresql/data" ] }
    @app_template.update!(accessories: [ db ])

    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    assert_equal [ db ], install.accessories
    assert_equal [ db ], install.deploy_envelope(image: "img@sha256:#{'a' * 64}")[:app][:accessories]

    # Copied, not followed: editing the library later must not change what a placed app runs.
    @app_template.update!(accessories: [])
    assert_equal [ db ], install.reload.accessories
  end

  # An accessory keeps data on *that box's* disk, exactly like a volume — so an install
  # that brings one is single-placement for the same reason, and the count gate that
  # already exists refuses more than one box.
  test "an accessory with a volume makes the install single-placement" do
    sign_in_as @user
    @app_template.update!(accessories: [ { "name" => "db", "image" => "p@sha256:#{'b' * 64}",
                                  "volumes" => [ "db-data:/data" ] } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    assert_not install.replicable?
    install.count = 3
    install.exposure = "balanced"
    assert_not install.valid?, "an install with a stateful accessory asked for three boxes"
  end

  test "a stateless accessory leaves the install replicable" do
    sign_in_as @user
    @app_template.update!(accessories: [ { "name" => "cache", "image" => "redis@sha256:#{'c' * 64}" } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }

    assert Install.last.replicable?
  end

  test "the ceremony shows the accessories it will bring up" do
    sign_in_as @user
    @app_template.update!(accessories: [ { "name" => "db", "image" => "postgres@sha256:#{'b' * 64}" } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    get new_machine_mutation_path(@operator, act: "deploy", install_id: install.id,
                                  image: install.image, hostname: install.hostname)

    assert_select ".spec", /accessory/
    assert_select ".spec dd", /db · postgres@sha256/
    assert_select ".ceremony .note", /network only #{install.name} joins/
  end

  # ── Secret values ──────────────────────────────────────────────────────────
  # The console holds them encrypted and resends them every deploy, so a deploy is
  # self-contained (decisions/declarative-deploy.md). They ride stdin, never argv, and
  # are never recorded.
  def configured_install
    @app_template.update!(env: [ { "key" => "RAILS_ENV", "secret" => false },
                        { "key" => "SECRET_KEY_BASE", "secret" => true } ],
                 secret_files: [ { "name" => "creds", "path" => "/etc/app/creds.json" } ],
                 accessories: [ { "name" => "db", "image" => "p@sha256:#{'b' * 64}",
                                  "secrets" => [ "POSTGRES_PASSWORD" ] } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    Install.last
  end

  test "every declared name is asked for, the accessory's included" do
    sign_in_as @user
    install = configured_install

    assert_equal %w[SECRET_KEY_BASE creds POSTGRES_PASSWORD].sort,
                 install.declared_secret_names.sort
    assert_equal %w[SECRET_KEY_BASE creds POSTGRES_PASSWORD].sort,
                 install.missing_secrets.sort
  end

  test "configuring stores values encrypted and never records them" do
    sign_in_as @user
    install = configured_install

    assert_no_difference -> { Event.count } do
      patch configure_install_path(install), params: { install: {
        env: { "RAILS_ENV" => "production" },
        secret_values: { "SECRET_KEY_BASE" => "s3cret", "creds" => "{}",
                         "POSTGRES_PASSWORD" => "pgpass" }
      } }
    end
    install.reload

    assert_empty install.missing_secrets
    assert_equal "production", install.config.dig("env", "RAILS_ENV")
    # At rest it is ciphertext — the same protection a machine's private key gets.
    raw = Install.connection.select_value("select secret_values from installs where id=#{install.id}")
    assert_no_match(/s3cret/, raw)
  end

  test "the envelope carries the values, bound to the names the spec declares" do
    sign_in_as @user
    install = configured_install
    install.update!(secret_values: { "SECRET_KEY_BASE" => "s", "creds" => "{}",
                                     "POSTGRES_PASSWORD" => "p", "GONE" => "stale" })

    envelope = install.deploy_envelope(image: "img@sha256:#{'a' * 64}")

    assert_equal [ "SECRET_KEY_BASE" ], envelope[:app][:secrets]
    assert_equal({ "creds" => "/etc/app/creds.json" }, envelope[:app][:secret_files])
    assert_equal %w[SECRET_KEY_BASE creds POSTGRES_PASSWORD].sort,
                 envelope[:secret_values].keys.sort
    # A value left over from a name the library has dropped is not handed to a box.
    assert_not envelope[:secret_values].key?("GONE")
  end

  # A password field renders empty by design, so an empty box means "leave it alone".
  # Treating it as a deletion would wipe every secret you did not retype.
  test "a blank field leaves the stored value alone" do
    sign_in_as @user
    install = configured_install
    install.update!(secret_values: { "SECRET_KEY_BASE" => "keep", "creds" => "{}",
                                     "POSTGRES_PASSWORD" => "p" })

    patch configure_install_path(install), params: { install: {
      secret_values: { "SECRET_KEY_BASE" => "", "creds" => "", "POSTGRES_PASSWORD" => "rotated" }
    } }

    assert_equal "keep", install.reload.secret_values["SECRET_KEY_BASE"]
    assert_equal "rotated", install.secret_values["POSTGRES_PASSWORD"]
  end

  # A stored secret is never sent back to a page. The panel says whether one is held.
  test "the install page never renders a stored secret" do
    sign_in_as @user
    install = configured_install
    install.update!(secret_values: { "SECRET_KEY_BASE" => "topsecretvalue" })

    get install_path(install)

    assert_response :success
    assert_no_match(/topsecretvalue/, response.body)
    # The field says a value is held and offers to replace it — that is the whole of
    # what a read of this page ever learns about a stored secret.
    assert_select "input[type=password][name=?][placeholder=?]",
                  "install[secret_values][SECRET_KEY_BASE]", "A value is held — type to replace it"
    # And the one with nothing behind it says so instead.
    assert_select ".panel.config", /No value yet/
  end

  # The box refuses a declared name with no value, every time — so this is a certainty,
  # not a stale reading, and the console refuses before writing an Event at all.
  test "a deploy missing a secret is refused before anything is recorded" do
    sign_in_as @user
    install = configured_install

    assert_no_difference -> { Event.count } do
      post machine_mutation_path(@operator, act: "deploy", install_id: install.id,
                                 image: install.image, hostname: install.hostname)
    end
    assert_match(/SECRET_KEY_BASE/, flash[:alert])
    assert_match(/Configuration/, flash[:alert])
  end

  # ── Processes reach the box ────────────────────────────────────────────────
  test "an install copies the app's processes and carries them in the envelope" do
    sign_in_as @user
    worker = { "name" => "worker", "command" => [ "bin/jobs" ] }
    @app_template.update!(processes: [ worker ])

    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    assert_equal [ worker ], install.processes
    assert_equal [ worker ], install.deploy_envelope(image: "img@sha256:#{'a' * 64}")[:app][:processes]

    # Copied, not followed — the whole point is that a placed app's worker cannot change
    # under it.
    @app_template.update!(processes: [])
    assert_equal [ worker ], install.reload.processes
  end

  # A process runs the app's own image, so it does not make the install stateful the way
  # an accessory with a volume does — nothing new is kept on that box's disk.
  test "a process leaves the install replicable" do
    sign_in_as @user
    @app_template.update!(processes: [ { "name" => "worker", "command" => [ "bin/jobs" ] } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }

    assert Install.last.replicable?
  end

  test "the ceremony shows the processes it will start" do
    sign_in_as @user
    @app_template.update!(processes: [ { "name" => "worker", "command" => [ "bin/jobs" ] } ])
    post installs_path(project_id: @project), params: { install: {
      app_template_id: @app_template.id, machine_id: @operator.id, hostname: "acme.example"
    } }
    install = Install.last

    get new_machine_mutation_path(@operator, act: "deploy", install_id: install.id,
                                  image: install.image, hostname: install.hostname)

    assert_select ".spec", /process/
    assert_select ".spec dd", "worker · bin/jobs"
  end
end
