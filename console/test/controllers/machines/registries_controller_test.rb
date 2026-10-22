require "test_helper"

# Logging a box into a registry: a recorded act that carries a password. The password
# rides stdin and is kept nowhere.
class Machines::RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @machine = Machine.create!(name: "edge-1", ssh_host: "10.0.0.1", scope: "operate",
                               ssh_private_key: "k")
  end

  test "the form says what runs and what is recorded" do
    sign_in_as @user
    get new_machine_registry_path(@machine)
    assert_response :success
    assert_select "form[action=?]", machine_registry_path(@machine)
    assert_select "input[type=password][name=password]"
    assert_select "body", /does not keep it/
  end

  test "logging in sends the registry and username on the command, the password on stdin" do
    sign_in_as @user
    with_fake_vilice do |vilice|
      vilice.on(/registry-login/, data: { "ok" => true, "message" => "logged in" })
      assert_difference -> { Event.count }, 1 do
        post machine_registry_path(@machine), params: { registry: "ghcr.io", username: "me", password: "s3cret-token" }
      end
      assert vilice.issued?("registry-login ghcr.io --username me --json")
      assert_equal "s3cret-token", vilice.stdin_for(/registry-login/)
    end
    assert_redirected_to status_machine_path(@machine, anchor: "registries")

    event = Event.order(:id).last
    assert_equal "logged in", event.action
    assert_equal "ok", event.outcome
    # The password is in no column of the entry.
    assert_no_match(/s3cret-token/, event.attributes.to_json)
  end

  test "a registry or username that could carry a flag is refused before the box is asked" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      post machine_registry_path(@machine), params: { registry: "ghcr.io --all", username: "me", password: "x" }
      assert_response :unprocessable_entity
      post machine_registry_path(@machine), params: { registry: "ghcr.io/acme", username: "me", password: "x" }
      assert_response :unprocessable_entity
      post machine_registry_path(@machine), params: { registry: "ghcr.io", username: "--password", password: "x" }
      assert_response :unprocessable_entity
      post machine_registry_path(@machine), params: { registry: "ghcr.io", username: "me", password: "" }
      assert_response :unprocessable_entity
    end
  end

  test "a refused login stays on the form with the box's reason" do
    sign_in_as @user
    stub_mutate(result: { ok: false, error: "unauthorized: bad credentials" }) do
      post machine_registry_path(@machine), params: { registry: "ghcr.io", username: "me", password: "x" }
    end
    assert_response :unprocessable_entity
    assert_select ".flash.alert", /bad credentials/
    # The password is not echoed back into the form.
    assert_select "input[name=password][value]", count: 0
  end

  test "an observe key cannot log the box in" do
    sign_in_as @user
    observer = Machine.create!(name: "ro", ssh_host: "10.0.0.2", scope: "observe")
    stub_mutate(refuse: true) do
      post machine_registry_path(observer), params: { registry: "ghcr.io", username: "me", password: "x" }
    end
    assert_redirected_to observer
  end

  # Logging out carries no secret, so it is an ordinary ceremony act.
  test "logging out is previewed, then sent" do
    sign_in_as @user
    get new_machine_mutation_path(@machine, act: "registry-logout", registry: "ghcr.io", frame: "ceremony-registries")
    assert_select "turbo-frame#ceremony-registries", /vilice registry-logout ghcr\.io --json/

    called = stub_mutate do
      post machine_mutation_path(@machine, act: "registry-logout", registry: "ghcr.io")
    end
    assert_equal "registry-logout ghcr.io --json", called[:command]
    assert_equal "logged out", called[:action]
  end

  test "a registry-logout with no valid registry is not an act" do
    sign_in_as @user
    stub_mutate(refuse: true) do
      post machine_mutation_path(@machine, act: "registry-logout", registry: "ghcr.io --all")
    end
    assert_redirected_to @machine
  end
end
