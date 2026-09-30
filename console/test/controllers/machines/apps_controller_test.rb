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
    assert_select ".cmd-block pre.cmd", "steward deploy web --json"
    # The raw spec shows the envelope the box reads, with the secret value masked.
    assert_select ".raw-output pre.raw", /"secret_values"/
    assert_select ".raw-output pre.raw", text: /hunter2/, count: 0
  end

  # The acceptance test for the whole layer: a deploy that touches no Project and
  # leaves no App behind, sending the envelope `steward deploy` reads.
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

  test "removing an app is a recorded act on the box" do
    sign_in_as @user
    called = stub_mutate do
      deploying { delete machine_box_app_path(@machine, "web") }
    end
    assert_equal "remove web --json", called[:command]
    assert_redirected_to @machine
  end
end
