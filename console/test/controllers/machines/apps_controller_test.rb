require "test_helper"

# The machine view's deploy surface: deploy to one box with no Project, no App, and
# nothing stored. The config is transit — it goes to the box and is discarded.
class Machines::AppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @machine = Machine.create!(name: "edge-1", ssh_host: "10.0.0.1", scope: "operate")
  end

  HOST = { ok: true, data: { "data" => { "role" => "host" } } }.freeze

  def deploying(&block)
    stub_observe(status: HOST, &block)
  end

  test "the deploy form is behind the login" do
    get new_machine_box_app_path(@machine)
    assert_redirected_to new_session_path
  end

  IMAGE = "ghcr.io/x/y@sha256:#{'abc' * 21}a".freeze
  FIELDS = { name: "web", image: IMAGE, hostnames: "a.example.com\nwww.a.example.com",
             port: "8080", env: "RAILS_ENV=production", secrets: "SECRET_KEY_BASE=hunter2" }.freeze

  # Submitting the form previews: the plain reading, the command, the exact envelope —
  # and nothing is sent.
  test "the form previews the deploy without calling the box" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      deploying { post machine_box_apps_path(@machine), params: { box_deploy: FIELDS } }
    end
    assert_response :success
    assert_select ".ceremony .facts dd", /a\.example\.com, www\.a\.example\.com/
    assert_select ".ceremony .facts dd", "SECRET_KEY_BASE"
    assert_select ".cmd-block pre.cmd", "vilice deploy web --json"
    # The raw spec shows the envelope the box reads, with the secret value masked.
    assert_select ".raw-output pre.raw", /"secret_values"/
    assert_select ".raw-output pre.raw", text: /hunter2/, count: 0
  end

  # The acceptance test for the whole layer: a deploy that touches no Project and
  # leaves no App behind, sending the envelope `vilice deploy` reads.
  test "confirming deploys with no project, stores nothing, and sends the box's envelope" do
    sign_in_as @user
    called = stub_mutate do
      deploying { post machine_box_apps_path(@machine), params: { box_deploy: FIELDS, confirm: "1" } }
    end

    assert_redirected_to @machine
    assert_equal "deploy web --json", called[:command]
    assert_nil called[:app], "a machine-view deploy must not create or reference an App"
    assert_equal 0, App.count, "nothing may be stored on the console side"

    # The spec rides stdin, never the command line; secret values ride beside it.
    envelope = JSON.parse(called[:stdin])
    assert_equal IMAGE, envelope.dig("app", "image")
    assert_equal %w[ a.example.com www.a.example.com ], envelope.dig("app", "hostnames")
    assert_equal 8080, envelope.dig("app", "port")
    assert_equal({ "RAILS_ENV" => "production" }, envelope.dig("app", "env"))
    assert_equal %w[ SECRET_KEY_BASE ], envelope.dig("app", "secrets")
    assert_equal({ "SECRET_KEY_BASE" => "hunter2" }, envelope["secret_values"])
    assert_not_includes called[:command], "hunter2"
  end

  test "a template fills the form" do
    sign_in_as @user
    template = AppTemplate.create!(name: "shop", port: 3000, health: "/up",
                                   env: [ { "key" => "RAILS_ENV" }, { "key" => "SECRET_KEY_BASE", "secret" => true } ],
                                   release: %w[ bin/rails db:migrate ])
    template.versions.create!(tag: "v1", image: IMAGE, latest: true)
    deploying { get new_machine_box_app_path(@machine, template_id: template.id) }
    assert_select "input[name=?][value=?]", "box_deploy[image]", IMAGE
    assert_select "input[name=?][value=?]", "box_deploy[port]", "3000"
    assert_select "textarea[name=?]", "box_deploy[secrets]", text: /SECRET_KEY_BASE=/
    # What the form has no field for rides along, into the spec.
    assert_equal %w[ bin/rails db:migrate ], JSON.parse(css_select("input[name='box_deploy[extras]']").first["value"])["release"]
  end

  test "a pasted spec replaces the fields, whether spec or whole envelope" do
    sign_in_as @user
    [ { "image" => IMAGE, "hostnames" => [ "p.example.com" ] },
      { "app" => { "image" => IMAGE, "hostnames" => [ "p.example.com" ] } } ].each do |pasted|
      called = stub_mutate do
        deploying do
          post machine_box_apps_path(@machine), params: { box_deploy: { name: "web", pasted: pasted.to_json }, confirm: "1" }
        end
      end
      assert_equal [ "p.example.com" ], JSON.parse(called[:stdin]).dig("app", "hostnames")
    end
  end

  test "refuses what the form must check, without calling the box" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      deploying { post machine_box_apps_path(@machine), params: { box_deploy: { name: "web", pasted: "not json" }, confirm: "1" } }
    end
    assert_response :unprocessable_entity
    assert_match(/is not a JSON object/, response.body)

    stub_mutate(refuse: true) do
      deploying { post machine_box_apps_path(@machine), params: { box_deploy: { name: "-web", image: "" } } }
    end
    assert_response :unprocessable_entity
    assert_match(/Image is required/, response.body)
    assert_match(/must start with a letter or digit/, response.body)
  end

  # Buttons follow the key. The box would refuse it anyway; we do not offer it.
  test "an observe-scoped machine has no deploy surface" do
    sign_in_as @user
    observer = Machine.create!(name: "read-only", ssh_host: "10.0.0.2", scope: "observe")
    deploying { get new_machine_box_app_path(observer) }
    assert_redirected_to observer
    assert_match(/observe-only/, flash[:alert])
  end

  # And no surface on a box whose role is not to run apps — absent, not disabled.
  test "a balancer has no deploy surface" do
    sign_in_as @user
    edge = { ok: true, data: { "data" => { "role" => "balancer" } } }
    stub_observe(status: edge) { get new_machine_box_app_path(@machine) }
    assert_redirected_to @machine
    assert_match(/balancer/, flash[:alert])
  end

  # But an unreachable box keeps its deploy surface: no role read is unknown, not
  # balancer, and we do not take a surface away on a guess.
  test "an unreachable box keeps its deploy surface" do
    sign_in_as @user
    stub_observe { get new_machine_box_app_path(@machine) }
    assert_response :success
  end

  # The preview is a 200 page in reply to a post. Turbo shows nothing for that — it
  # wants a redirect — so with Turbo on, pressing Preview left the form on screen.
  test "the deploy form and its preview post without Turbo" do
    sign_in_as @user
    deploying { get new_machine_box_app_path(@machine) }
    assert_select "form.stack-form[action=?][data-turbo=false]", machine_box_apps_path(@machine)
    deploying { post machine_box_apps_path(@machine), params: { box_deploy: FIELDS } }
    assert_select "form[action=?][data-turbo=false] button[name=confirm]", machine_box_apps_path(@machine)
  end

  # ── One app on this box ────────────────────────────────────────────────────
  STRAY_IMAGE = "docker.io/stray@sha256:#{'0' * 64}".freeze

  def reporting(*apps, backups: nil)
    data = { "role" => "host", "apps" => apps }
    data["backups"] = backups if backups
    stub_observe(status: { ok: true, at: Time.current, data: { "data" => data } }) { yield }
  end

  # An app deployed from the machine page keeps no App here. It still has a page, and
  # every act on it works from its name.
  test "an app the box reports has a page, with its acts, though we hold no App for it" do
    sign_in_as @user
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "running" },
              backups: { "configured" => true, "targets" => { "stray" => { "last_ok" => 2.hours.ago.iso8601 } } }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_response :success
    assert_select "h1 .app-state", /running/
    assert_select "table.facts-table th", "Placement"
    assert_select "table.facts-table td", /\Anone\z/
    # Each thing about it is a part that leads with how it is.
    %w[running deploy backups remove].each { |part| assert_select "section.status-part##{part} .status-summary" }
    assert_select "section#running .status-summary", "Running"
    assert_select ".read-bar form[action=?]", refresh_machine_path(@machine, from: "box", name: "stray")
    %w[restart stop start rollback backup restore remove].each do |verb|
      assert_select "a.btn.cmd[href*=?]", "act=#{verb}&", text: verb
    end
    assert_select "a.btn.cmd[href=?]",
                  new_machine_mutation_path(@machine, act: "restart", frame: "ceremony-run", from: "box", name: "stray")
    assert_select "turbo-frame#ceremony-run"
    assert_select "section#backups.is-ok .status-summary", /Backed up/
    # No stored spec to send, so deploy is the box's own form, with the name filled in.
    assert_select "a.btn.cmd[href=?]", new_machine_box_app_path(@machine, name: "stray"), text: "deploy"
    assert_select "a.logs-link[href=?]", machine_logs_path(@machine, name: "stray")
  end

  # The box's words are Podman's, so the colour is read off how they begin.
  test "an app that is up reads green, a stopped one grey, an exited one red" do
    sign_in_as @user
    { "Up 6 minutes" => "green", "stopped" => "gray", "Exited (1) 2 minutes ago" => "red" }.each do |state, color|
      reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => state }) do
        get machine_box_app_path(@machine, "stray")
      end
      assert_select "h1 .app-state .dot.dot-#{color}", { count: 1 }, "#{state.inspect} should be #{color}"
    end
  end

  # A stopped app has no container. The box still lists it, and its page still offers
  # the way back.
  test "a stopped app keeps its page, and can be started" do
    sign_in_as @user
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "stopped" }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select "h1 .app-state", /stopped/
    assert_select "a.btn.cmd[href*=?]", "act=start&", text: "start"
  end

  test "rollback is inert when the box says there is no earlier image" do
    sign_in_as @user
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "Up 1 minute", "rollback" => false }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select ".act", /Nothing to go back to/ do
      assert_select ".btn.cmd[aria-disabled=true]", "rollback"
    end
    assert_select "a[href*=?]", "act=rollback", count: 0

    # A box that does not say keeps the button: unknown is not "nothing".
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "Up 1 minute" }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select "a.btn.cmd[href*=?]", "act=rollback&"
  end

  # Every hostname is a link that opens the app; a wildcard names no one address.
  test "an app's page lists every hostname it answers at, each opening in a new tab" do
    sign_in_as @user
    hosts = [ "stray.example", "http://plain.example", "*.wild.example" ]
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "Up 1 minute", "hostnames" => hosts }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select ".facts-table .host-list a.host[href=?][target=_blank]", "https://stray.example", text: /stray\.example/
    assert_select ".facts-table .host-list a.host[href=?]", "http://plain.example"
    assert_select ".facts-table .host-list span.host", "*.wild.example"
    assert_select ".facts-table .host-list a[href*=?]", "wild", count: 0
  end

  # Caddy keeps certificates for the box, but each belongs to one app's hostname.
  test "an app's page shows where it answers, with that hostname's certificate" do
    sign_in_as @user
    certs = [ { "host" => "stray.example", "not_after" => 60.days.from_now.iso8601, "issuer" => "R11", "valid" => true },
              { "host" => "other.example", "not_after" => 60.days.from_now.iso8601, "issuer" => "R11", "valid" => true } ]
    data = { "role" => "host", "certs" => certs,
             "apps" => [ { "name" => "stray", "image" => STRAY_IMAGE, "state" => "Up 1 minute", "hostnames" => [ "stray.example" ] } ] }
    stub_observe(status: { ok: true, at: Time.current, data: { "data" => data } }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select "section#certificates" do
      assert_select ".status-summary", "1 valid"
      assert_select ".fact-rows li", count: 1
      assert_select ".fact-rows li", /stray\.example.*Valid/m
    end
  end

  test "an app we hold an App for links to it, and deploys that App's spec" do
    sign_in_as @user
    app = App.create!(name: "web", image: STRAY_IMAGE)
    app.placements.create!(machine: @machine, status: "running")
    reporting({ "name" => "web", "image" => STRAY_IMAGE, "state" => "running" }) do
      get machine_box_app_path(@machine, "web")
    end
    assert_select ".facts-table a[href=?]", app_path(app)
    assert_select "a.btn.cmd[href*=?]", "act=deploy&app_id=#{app.id}", text: "deploy"
  end

  test "an app that has never backed up is not offered a restore" do
    sign_in_as @user
    reporting({ "name" => "stray", "image" => STRAY_IMAGE, "state" => "running" },
              backups: { "configured" => true, "targets" => {} }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select "section#backups.is-warn .status-summary", "Never backed up"
    assert_select "a[href*=?]", "act=restore", count: 0
    assert_select ".btn.cmd[aria-disabled=true]", "restore"
  end

  test "an observe key reads the page and is offered no act" do
    sign_in_as @user
    observer = Machine.create!(name: "ro", ssh_host: "10.0.0.2", scope: "observe")
    stub_observe(status: { ok: true, at: Time.current,
                           data: { "data" => { "role" => "host", "apps" => [ { "name" => "stray", "image" => STRAY_IMAGE, "state" => "running" } ] } } }) do
      get machine_box_app_path(observer, "stray")
    end
    assert_response :success
    assert_select ".observe-only"
    assert_select "a[href*=?]", "act=", count: 0
    assert_select "a.logs-link"   # reading is still offered
  end

  test "an unreachable box says so, and offers no act" do
    sign_in_as @user
    stub_observe { get machine_box_app_path(@machine, "stray") }
    assert_response :success
    assert_select ".panel.unreachable"
    assert_select "a[href*=?]", "act=", count: 0
  end

  test "reading again from an app's page returns there" do
    sign_in_as @user
    stub_observe { post refresh_machine_path(@machine, from: "box", name: "stray") }
    assert_redirected_to machine_box_app_path(@machine, "stray")
    stub_observe { post refresh_machine_path(@machine, from: "box", name: "-rf") }
    assert_redirected_to @machine
  end

  test "an app's page shows how much of the box it is using" do
    sign_in_as @user
    data = { "role" => "host", "machine" => { "mem_total_kb" => 4_000_000, "mem_available_kb" => 2_000_000 },
             "apps" => [ { "name" => "stray", "image" => STRAY_IMAGE, "state" => "Up 1 minute", "memory_bytes" => 512 * 1024 * 1024 } ] }
    stub_observe(status: { ok: true, at: Time.current, data: { "data" => data } }) do
      get machine_box_app_path(@machine, "stray")
    end
    assert_select "section#running .usage", /Memory.*13%.*512 MB of 3.81 GB/m
  end

  test "a name the box does not report says so rather than failing" do
    sign_in_as @user
    reporting { get machine_box_app_path(@machine, "ghost") }
    assert_response :success
    assert_select ".panel", /does not report an app named/
    assert_select "a[href*=?]", "act=restart", count: 0
  end

  test "a name that is not an app name is turned away" do
    sign_in_as @user
    stub_observe { get machine_box_app_path(@machine, "-rf") }
    assert_redirected_to @machine
  end

  # ── Acts by name, through the ceremony ─────────────────────────────────────
  test "the ceremony previews an act on a named app, in the frame it was asked for" do
    sign_in_as @user
    get new_machine_mutation_path(@machine, act: "restart", name: "stray", from: "box", frame: "ceremony-run")
    assert_response :success
    assert_select "turbo-frame#ceremony-run", /vilice restart stray --json/
  end

  test "removing an app is a recorded act on the box, and lands back on the machine" do
    sign_in_as @user
    called = stub_mutate do
      post machine_mutation_path(@machine, act: "remove", name: "web", from: "box")
    end
    assert_equal "remove web --json", called[:command]
    assert_redirected_to @machine
  end

  test "backing up an app returns to its page" do
    sign_in_as @user
    called = stub_mutate do
      post machine_mutation_path(@machine, act: "backup", name: "web", from: "box")
    end
    assert_equal "backup web --json", called[:command]
    assert_equal "backed up", called[:action]
    assert_redirected_to machine_box_app_path(@machine, "web")
  end

  test "a name that could carry a flag never reaches a command" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      post machine_mutation_path(@machine, act: "remove", name: "web --all", from: "box")
    end
    assert_redirected_to @machine
    assert_match(/invalid/i, flash[:alert])
  end

  test "a frame id that is not a ceremony frame falls back to the default" do
    sign_in_as @user
    get new_machine_mutation_path(@machine, act: "restart", name: "stray", frame: "machine-live")
    assert_select "turbo-frame#ceremony"
  end
end
