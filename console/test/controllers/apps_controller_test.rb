require "test_helper"

# The App Library catalog — CRUD, gated by login, each change recorded as an
# attributed own-record act (decisions/open/app-library.md).
class AppsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "the library is behind the login" do
    get apps_path
    assert_redirected_to new_session_path
  end

  test "index renders the list, search, and the sidebar link" do
    sign_in_as @user
    App.create!(name: "nginx")
    App.create!(name: "billing")
    get apps_path
    assert_response :success
    assert_select "h1", /App Library/
    assert_select ".nav[href=?]", apps_path                 # sidebar entry
    assert_select ".app-rows .row-name", /nginx/            # stacked list

    get apps_path(q: "nginx")
    assert_select ".app-rows .row-name", { count: 1, text: "nginx" }  # search filters
  end

  test "index shows the manage toolbar — select-all, search, and a disabled bulk action" do
    sign_in_as @user
    App.create!(name: "nginx")
    get apps_path
    assert_select ".list-managed[data-controller=selection]"
    assert_select ".toolbar-select input[data-selection-target=all]"
    assert_select ".toolbar-search input[name=q]"
    assert_select ".toolbar-search input[type=submit][value=Search]"
    assert_select "button[form=apps-bulk][disabled][data-selection-target=action]"
    assert_select ".row-select[data-selection-target=item]", count: 1
    # Import menu offers both a file and a URL source; Export is present.
    assert_select "details.menu input[type=file]"
    assert_select "details.menu input[type=url]"
    assert_select "a[href=?]", export_apps_path
  end

  test "show lists the app's versions" do
    sign_in_as @user
    app = App.create!(name: "web")
    v = app.versions.create!(tag: "v1.2.0", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
    app.set_latest!(v)
    get app_path(app)
    assert_response :success
    assert_select ".version-tag", /v1.2.0/
    assert_select ".tag.latest"
  end

  test "adding an app records the act and goes to its page" do
    sign_in_as @user
    assert_difference [ -> { App.count }, -> { Event.count } ], 1 do
      post apps_path, params: { app: { name: "web", port: 8080 } }
    end
    app = App.find_by(name: "web")
    assert_redirected_to app                                # → show, to add a version
    assert_equal 8080, app.port
    event = Event.latest.first
    assert_equal "added", event.action
    assert_equal @user.email_address, event.actor
  end

  test "an invalid app neither persists nor records" do
    sign_in_as @user
    assert_no_difference [ -> { App.count }, -> { Event.count } ] do
      post apps_path, params: { app: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "editing records the change" do
    sign_in_as @user
    app = App.create!(name: "web", description: "old")
    assert_difference -> { Event.count }, 1 do
      patch app_path(app), params: { app: { description: "new" } }
    end
    assert_equal "new", app.reload.description
    assert_equal "edited", Event.latest.first.action
  end

  test "the inputs editor saves env (with a secret flag) and secret files" do
    sign_in_as @user
    app = App.create!(name: "web")
    patch app_path(app), params: { app: {
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

  test "removing an app records it and leaves the record intact" do
    sign_in_as @user
    app = App.create!(name: "web")
    assert_difference [ -> { App.count } ], -1 do
      assert_difference -> { Event.count }, 1 do
        delete app_path(app)
      end
    end
    assert_equal "removed", Event.latest.first.action
  end

  test "export streams the library as a yaml attachment" do
    sign_in_as @user
    App.create!(name: "web")
    get export_apps_path
    assert_response :success
    assert_match %r{attachment.*console-library\.yml}, response.headers["Content-Disposition"]
    assert_equal 1, YAML.safe_load(response.body)["apps"].size
  end

  test "import merges a manifest and records one act naming the apps" do
    sign_in_as @user
    manifest = { "format" => 1, "apps" => [ { "name" => "abc" }, { "name" => "xyz" } ] }
    file = Rack::Test::UploadedFile.new(StringIO.new(manifest.to_yaml), "text/yaml",
                                        original_filename: "vendor.yml")
    assert_difference [ -> { App.count } ], 2 do
      assert_difference -> { Event.count }, 1 do
        post import_apps_path, params: { file: file }
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
    assert_no_difference [ -> { App.count }, -> { Event.count } ] do
      post import_apps_path, params: { file: file }
    end
    assert_redirected_to apps_path
  end

  test "remove selected bulk-deletes and records one act" do
    sign_in_as @user
    a = App.create!(name: "a")
    b = App.create!(name: "b")
    App.create!(name: "keep")
    assert_difference [ -> { App.count } ], -2 do
      assert_difference -> { Event.count }, 1 do
        delete remove_selected_apps_path, params: { ids: [ a.id, b.id ] }
      end
    end
    assert_equal "removed", Event.latest.first.action
    assert_equal %w[ keep ], App.pluck(:name)
  end

  # The chip editor is quick to toggle and hard to audit. The mistake that matters is a
  # variable that should have been secret and was not — its value then lands in an
  # append-only record and cannot be taken back — so the declaration is read back a
  # second time, sorted, split by what actually happens to the value.
  test "the app page reads its declaration back in two sorted columns" do
    sign_in_as @user
    app = App.create!(name: "zot", env: [
      { "key" => "LOG_LEVEL", "secret" => false },
      { "key" => "DATABASE_PASSWORD", "secret" => true },
      { "key" => "API_URL", "secret" => false },
      { "key" => "S3_SECRET_KEY", "secret" => true } ])

    get app_path(app)
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
    app = App.create!(name: "bare")
    get app_path(app)
    assert_select ".declared .empty", 2
  end

  # The browser refuses it before the round trip; the model refuses it regardless.
  test "the version form asks for a digest-pinned image" do
    sign_in_as @user
    app = App.create!(name: "pinned")
    get app_path(app)
    assert_select "input[name=?][pattern=?]", "version[image]", ".+@sha256:[0-9a-f]{64}"
  end

  test "a floating tag is refused, and the app page says why" do
    sign_in_as @user
    app = App.create!(name: "floating")
    assert_no_difference -> { Version.count } do
      post app_versions_path(app), params: { version: { tag: "v1", image: "ghcr.io/a/b:latest" } }
    end
    assert_match(/digest-pinned/, response.body)
  end
end
