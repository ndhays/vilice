require "test_helper"

# The App Library catalog — CRUD, gated by login, each change recorded as an
# attributed own-record act (decisions/open/app-library.md).
class AppTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "the library is behind the login" do
    get app_templates_path
    assert_redirected_to new_session_path
  end

  test "index renders the list, search, and the sidebar link" do
    sign_in_as @user
    AppTemplate.create!(name: "nginx")
    AppTemplate.create!(name: "billing")
    get app_templates_path
    assert_response :success
    assert_select "h1", /App Library/
    assert_select ".nav[href=?]", app_templates_path                 # sidebar entry
    assert_select ".app-rows .row-name", /nginx/            # stacked list

    get app_templates_path(q: "nginx")
    assert_select ".app-rows .row-name", { count: 1, text: "nginx" }  # search filters
  end

  test "index shows the manage toolbar — select-all, search, and a disabled bulk action" do
    sign_in_as @user
    AppTemplate.create!(name: "nginx")
    get app_templates_path
    assert_select ".list-managed[data-controller=selection]"
    assert_select ".toolbar-select input[data-selection-target=all]"
    assert_select ".toolbar-search input[name=q]"
    assert_select ".toolbar-search input[type=submit][value=Search]"
    assert_select "button[form=apps-bulk][disabled][data-selection-target=action]"
    assert_select ".row-select[data-selection-target=item]", count: 1
    # Import menu offers both a file and a URL source; Export is present.
    assert_select "details.menu input[type=file]"
    assert_select "details.menu input[type=url]"
    assert_select "a[href=?]", export_app_templates_path
  end

  test "show lists the app's versions" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")
    v = app.versions.create!(tag: "v1.2.0", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    app.set_latest!(v)
    get app_template_path(app)
    assert_response :success
    assert_select ".version-tag", /v1.2.0/
    assert_select ".tag.latest"
  end

  test "adding an app records the act and goes to its page" do
    sign_in_as @user
    assert_difference [ -> { AppTemplate.count }, -> { Event.count } ], 1 do
      post app_templates_path, params: { app_template: { name: "web", port: 8080 } }
    end
    app = AppTemplate.find_by(name: "web")
    assert_redirected_to app                                # → show, to add a version
    assert_equal 8080, app.port
    event = Event.latest.first
    assert_equal "added", event.action
    assert_equal @user.email_address, event.actor
  end

  test "an invalid app neither persists nor records" do
    sign_in_as @user
    assert_no_difference [ -> { AppTemplate.count }, -> { Event.count } ] do
      post app_templates_path, params: { app_template: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "editing records the change" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", description: "old")
    assert_difference -> { Event.count }, 1 do
      patch app_template_path(app), params: { app_template: { description: "new" } }
    end
    assert_equal "new", app.reload.description
    assert_equal "edited", Event.latest.first.action
  end

  test "the inputs editor saves env (with a secret flag) and secret files" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")
    patch app_template_path(app), params: { app_template: {
      inputs_form: "1",
      env_rows: { "0" => { key: "LOG", secret: "0" }, "1" => { key: "TOKEN", secret: "1" },
                  "2" => { key: "", secret: "0" } }, # blank row dropped
      secret_file_rows: { "0" => { name: "config", path: "/etc/web/config" } }
    } }
    app.reload
    assert_equal [ { "key" => "LOG", "secret" => false },
                   { "key" => "TOKEN", "secret" => true } ], app.env
    assert_equal [ { "name" => "config", "path" => "/etc/web/config" } ], app.secret_files
    assert_equal "edited", Event.latest.first.action
  end

  # The bug: removing the last row leaves the editor with no rows key to post, and an
  # absent key was read as "leave it alone" — so the last secret file (or the last
  # variable) came back on every save and could not be deleted at all.
  test "removing the last secret file actually removes it" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", env: [ { "key" => "TOKEN", "secret" => true } ],
                      secret_files: [ { "name" => "config", "path" => "/etc/web/config" } ])
    patch app_template_path(app), params: { app_template: {
      inputs_form: "1",
      env_rows: { "0" => { key: "TOKEN", secret: "1" } }
      # no secret_file_rows at all — the editor posts none once the last row is gone
    } }
    assert_empty app.reload.secret_files
    assert_equal [ { "key" => "TOKEN", "secret" => true } ], app.env
  end

  test "removing the last variable actually removes it" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", env: [ { "key" => "ONLY", "secret" => false } ])
    patch app_template_path(app), params: { app_template: { inputs_form: "1" } }
    assert_empty app.reload.env
  end

  # …but the details form posts to the same action and carries neither key, and there
  # an absent key really does mean "leave it alone".
  test "editing name or port leaves the declaration untouched" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", env: [ { "key" => "TOKEN", "secret" => true } ],
                      secret_files: [ { "name" => "config", "path" => "/etc/web/config" } ])
    patch app_template_path(app), params: { app_template: { name: "web", port: 9090 } }
    app.reload
    assert_equal 9090, app.port
    assert_equal [ { "key" => "TOKEN", "secret" => true } ], app.env
    assert_equal [ { "name" => "config", "path" => "/etc/web/config" } ], app.secret_files
  end

  test "removing an app records it and leaves the record intact" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")
    assert_difference [ -> { AppTemplate.count } ], -1 do
      assert_difference -> { Event.count }, 1 do
        delete app_template_path(app)
      end
    end
    assert_equal "removed", Event.latest.first.action
  end

  test "export streams the library as a yaml attachment" do
    sign_in_as @user
    AppTemplate.create!(name: "web")
    get export_app_templates_path
    assert_response :success
    assert_match %r{attachment.*console-library\.yml}, response.headers["Content-Disposition"]
    assert_equal 1, YAML.safe_load(response.body)["apps"].size
  end

  test "import merges a manifest and records one act naming the apps" do
    sign_in_as @user
    manifest = { "format" => 1, "apps" => [ { "name" => "abc" }, { "name" => "xyz" } ] }
    file = Rack::Test::UploadedFile.new(StringIO.new(manifest.to_yaml), "text/yaml",
                                        original_filename: "vendor.yml")
    assert_difference [ -> { AppTemplate.count } ], 2 do
      assert_difference -> { Event.count }, 1 do
        post import_app_templates_path, params: { file: file }
      end
    end
    event = Event.latest.first
    assert_equal "imported", event.action
    assert_equal "abc, xyz", event.detail                     # reconstructable, one row
  end

  test "import refuses an unsupported format without changing anything" do
    sign_in_as @user
    file = Rack::Test::UploadedFile.new(StringIO.new({ "format" => 99 }.to_yaml), "text/yaml",
                                        original_filename: "bad.yml")
    assert_no_difference [ -> { AppTemplate.count }, -> { Event.count } ] do
      post import_app_templates_path, params: { file: file }
    end
    assert_redirected_to app_templates_path
  end

  test "remove selected bulk-deletes and records one act" do
    sign_in_as @user
    a = AppTemplate.create!(name: "a")
    b = AppTemplate.create!(name: "b")
    AppTemplate.create!(name: "keep")
    assert_difference [ -> { AppTemplate.count } ], -2 do
      assert_difference -> { Event.count }, 1 do
        delete remove_selected_app_templates_path, params: { ids: [ a.id, b.id ] }
      end
    end
    assert_equal "removed", Event.latest.first.action
    assert_equal %w[ keep ], AppTemplate.pluck(:name)
  end

  # The chip editor is quick to toggle and hard to audit. The mistake that matters is a
  # variable that should have been secret and was not — its value then lands in an
  # append-only record and cannot be taken back — so the declaration is read back a
  # second time, sorted, split by what actually happens to the value.
  test "the app page reads its declaration back in two sorted columns" do
    sign_in_as @user
    app = AppTemplate.create!(name: "zot", env: [
      { "key" => "LOG_LEVEL", "secret" => false },
      { "key" => "DATABASE_PASSWORD", "secret" => true },
      { "key" => "API_URL", "secret" => false },
      { "key" => "S3_SECRET_KEY", "secret" => true } ])

    get app_template_path(app)
    assert_response :success
    recorded = css_select(".declared-col:not(.is-secret) .declared-list li").map(&:text)
    secret   = css_select(".declared-col.is-secret .declared-list li").map(&:text)
    assert_equal %w[API_URL LOG_LEVEL], recorded          # alphabetical, so it can be scanned
    assert_equal %w[DATABASE_PASSWORD S3_SECRET_KEY], secret
    # The columns name the consequence, not the word "secret" — the failure is not
    # knowing what the flag does.
    assert_select ".declared-col:not(.is-secret) h4", /Written to the record/
    assert_select ".declared-col.is-secret h4", /Never recorded/
  end

  test "an app with no declared variables says so in both columns" do
    sign_in_as @user
    app = AppTemplate.create!(name: "bare")
    get app_template_path(app)
    assert_select ".declared-none", 2
  end

  # The read-back is the resting state; editing is the deliberate act. Both halves stay
  # in the DOM, so toggling never discards an in-progress edit and the form posts as before.
  test "the declaration is what you see; the editor is behind a toggle" do
    sign_in_as @user
    app = AppTemplate.create!(name: "toggler", env: [ { "key" => "A", "secret" => false } ])
    get app_template_path(app)
    assert_response :success
    assert_select ".inputs:not(.editing)"                      # closed by default
    assert_select ".inputs .declared .declared-col", 2
    assert_select ".inputs-toggle[data-action=?]", "env-editor#toggle"
    # The editor is present but not the resting view — it still carries the form.
    assert_select ".inputs form.inputs-form input[name=?]", "app_template[env_rows][0][key]"
  end

  # Secret files are off-record by definition, so they belong in that column — marked as
  # files, because a path is a different kind of thing from a variable name.
  test "secret files are counted and listed with the never-recorded half" do
    sign_in_as @user
    app = AppTemplate.create!(name: "filed",
                      env: [ { "key" => "TOKEN", "secret" => true } ],
                      secret_files: [ { "name" => "htpasswd", "path" => "/etc/app/htpasswd" } ])
    get app_template_path(app)
    assert_select ".declared-col.is-secret .declared-count", "2"
    assert_select ".declared-col.is-secret .declared-list li.is-file", /htpasswd/
    assert_select ".declared-col.is-secret .declared-path", "/etc/app/htpasswd"
  end

  # The browser refuses it before the round trip; the model refuses it regardless.
  test "the version form asks for a digest-pinned image" do
    sign_in_as @user
    app = AppTemplate.create!(name: "pinned")
    get app_template_path(app)
    assert_select "input[name=?][pattern=?]", "version[image]", ".+@sha256:[0-9a-f]{64}"
  end

  test "a floating tag is refused, and the app page says why" do
    sign_in_as @user
    app = AppTemplate.create!(name: "floating")
    assert_no_difference -> { Version.count } do
      post app_template_versions_path(app), params: { version: { tag: "v1", image: "ghcr.io/a/b:latest" } }
    end
    assert_match(/digest-pinned/, response.body)
  end

  # ── The release command ────────────────────────────────────────────────────
  # Typed as a line, stored as argv, because argv is what the box execs — it never sees
  # a shell (blueprint/steward/deploy.md, "The Release Step").
  test "a release command is typed as a line and stored as argv" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    patch app_template_path(app), params: { app_template: { name: "web", release_line: "bin/rails db:migrate" } }

    assert_equal [ "bin/rails", "db:migrate" ], app.reload.release
  end

  test "clearing the line clears the command" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", release: [ "bin/rails", "db:migrate" ])

    patch app_template_path(app), params: { app_template: { name: "web", release_line: "" } }

    assert_empty app.reload.release
  end

  # The details form posts to the same action and carries no release field, and there
  # "leave it alone" is right — the same rule the env editor follows.
  test "a form that does not carry the field leaves the command alone" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", release: [ "bin/rails", "db:migrate" ])

    patch app_template_path(app), params: { app_template: { name: "web", port: 3000 } }

    assert_equal [ "bin/rails", "db:migrate" ], app.reload.release
  end

  test "the form says a shell is not available, rather than letting one be typed" do
    sign_in_as @user
    get edit_app_template_path(AppTemplate.create!(name: "web"))

    assert_select "input[name=?]", "app_template[release_line]"
    assert_select ".field small", /no shell/i
  end

  # ── Accessories ────────────────────────────────────────────────────────────
  # Typed as rows and stored in the box's own shape, so the deploy envelope is a copy
  # rather than a translation (decisions/accessories-belong-to-one-app.md).
  test "an accessory row is stored in the shape the box's spec uses" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1", accessory_rows: {
      "0" => { name: "db", image: "postgres@sha256:#{'b' * 64}",
               volumes: "db-data:/var/lib/postgresql/data",
               env: "POSTGRES_DB=app\nPOSTGRES_USER=app", secrets: "POSTGRES_PASSWORD" }
    } } }

    assert_equal [ { "name" => "db", "image" => "postgres@sha256:#{'b' * 64}",
                     "env" => { "POSTGRES_DB" => "app", "POSTGRES_USER" => "app" },
                     "secrets" => [ "POSTGRES_PASSWORD" ],
                     "volumes" => [ "db-data:/var/lib/postgresql/data" ] } ],
                 app.reload.accessories
  end

  test "a blank row is dropped, and removing the last one removes it" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web", accessories: [ { "name" => "db", "image" => "p@sha256:#{'b' * 64}" } ])

    patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1" } }

    assert_empty app.reload.accessories
  end

  # The mistakes the box would refuse are refused here, with a sentence, rather than at
  # deploy after someone has built an install on them.
  test "an accessory the box would refuse is refused where it is typed" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    [ { name: "db", image: "postgres:16" },                    # a tag, not a digest
      { name: "a",  image: "p@sha256:#{'b' * 64}" },           # a deploy color
      { name: "web", image: "p@sha256:#{'b' * 64}" },          # the app's own name
      { name: "db", image: "p@sha256:#{'b' * 64}", volumes: "/etc:/etc" } ].each do |row|
      patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1",
                                            accessory_rows: { "0" => row } } }
      assert_response :unprocessable_entity, "accepted #{row.inspect}"
      assert_empty app.reload.accessories
    end
  end

  # ── Processes ──────────────────────────────────────────────────────────────
  # The app's other containers — a worker, a clock. Typed as a line, stored as argv,
  # because the box execs it and never sees a shell.
  test "a process row is stored as name and argv" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1", process_rows: {
      "0" => { name: "worker", command: "bin/jobs --queue default" }
    } } }

    assert_equal [ { "name" => "worker", "command" => %w[bin/jobs --queue default] } ],
                 app.reload.processes
  end

  test "a process the box would refuse is refused where it is typed" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    [ { name: "worker", command: "" },       # nothing to run is not a process
      { name: "web",    command: "bin/jobs" } ].each do |row|
      patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1",
                                            process_rows: { "0" => row } } }
      assert_response :unprocessable_entity, "accepted #{row.inspect}"
      assert_empty app.reload.processes
    end
  end

  # Colours, processes and accessories all mint container names from the app's, and the
  # console checks the same set the box does — so this fails here, not at deploy.
  test "a process and an accessory cannot claim one container name" do
    sign_in_as @user
    app = AppTemplate.create!(name: "web")

    patch app_template_path(app), params: { app_template: { name: "web", inputs_form: "1",
      process_rows:   { "0" => { name: "worker", command: "bin/jobs" } },
      accessory_rows: { "0" => { name: "worker-a", image: "p@sha256:#{'b' * 64}" } } } }

    assert_response :unprocessable_entity
    assert_match(/would both be container/, response.body)
  end
end
