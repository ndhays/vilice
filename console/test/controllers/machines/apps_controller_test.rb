require "test_helper"

# The machine view's pack surface: deploy to one box with no Project, no Install, and
# nothing stored. The config is transit — it goes to the box and is discarded.
class Machines::AppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @machine = Machine.create!(name: "edge-1", ssh_host: "10.0.0.1", scope: "operate")
  end

  ACTIVE = { ok: true, data: { "data" => { "manifest" => "/etc/steward/packs.manifest",
    "packs" => [ { "name" => "steward-app", "state" => "active" } ] } } }.freeze

  CONFIG = '{"image":"ghcr.io/x/y@sha256:abc","hostnames":["a.example.com"],"port":8080}'.freeze

  def deploying(&block)
    stub_observe(packs: ACTIVE, &block)
  end

  test "the deploy form is behind the login" do
    get new_machine_box_app_path(@machine)
    assert_redirected_to new_session_path
  end

  # The acceptance test for the whole layer: a deploy that touches no Project and
  # leaves no Install behind.
  test "deploys with no project and stores nothing" do
    sign_in_as @user
    called = stub_mutate do
      deploying { post machine_box_apps_path(@machine), params: { name: "web", config: CONFIG } }
    end

    assert_redirected_to @machine
    assert_equal "deploy web --json", called[:command]
    assert_nil called[:install], "a machine-view deploy must not create or reference an Install"
    assert_equal 0, Install.count, "nothing may be stored on the console side"

    # The spec rides stdin, never the command line — that is what keeps secret
    # values out of the box's recorded invocation.
    assert_includes called[:stdin], "sha256:abc"
    assert_not_includes called[:command], "sha256:abc"
    assert_equal "web", JSON.parse(called[:stdin])["name"]
  end

  test "refuses a config that is not JSON, without calling the box" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      deploying { post machine_box_apps_path(@machine), params: { name: "web", config: "not json" } }
    end
    assert_response :unprocessable_entity
    assert_match(/not valid JSON/, response.body)
  end

  # Deploying under one name a spec that names another would file it under one and
  # describe the other.
  test "refuses a spec whose name disagrees with the deploy name" do
    sign_in_as @user
    deploying do
      post machine_box_apps_path(@machine), params: { name: "web", config: '{"name":"other","port":80}' }
    end
    assert_response :unprocessable_entity
    assert_match(/but you are deploying/, response.body)
  end

  # Buttons follow the key. The box would refuse it anyway; we do not offer it.
  test "an observe-scoped machine has no deploy surface" do
    sign_in_as @user
    observer = Machine.create!(name: "read-only", ssh_host: "10.0.0.2", scope: "observe")
    deploying { get new_machine_box_app_path(observer) }
    assert_redirected_to observer
    assert_match(/observe-only/, flash[:alert])
  end

  # And no surface on a box that does not run the pack — absent, not disabled.
  test "a box without steward-app has no deploy surface" do
    sign_in_as @user
    bare = { ok: true, data: { "data" => { "packs" => [] } } }
    stub_observe(packs: bare) { get new_machine_box_app_path(@machine) }
    assert_redirected_to @machine
    assert_match(/does not run steward-app/, flash[:alert])
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
