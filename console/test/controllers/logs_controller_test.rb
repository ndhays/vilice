require "test_helper"

# Reading an app's logs off the box. A read, not an act: `steward logs` is `observe`
# scope and a passthrough to `podman logs`, so nothing is recorded and nothing is
# mirrored into our own columns.
class LogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @project = Project.create!(name: "Acme")
    @machine = Machine.create!(name: "box", ssh_host: "10.0.0.2", scope: "operate",
                               ssh_private_key: "k", status: "reachable",
                               last_seen_at: Time.current, owner: @project)
    ProjectMachine.create!(project: @project, machine: @machine)
    @install = @project.installs.create!(name: "web", hostname: "acme.example",
                                         image: "img@sha256:#{'a' * 64}")
    @install.install_targets.create!(machine: @machine, status: "running")
  end

  test "logs are behind the login" do
    get machine_logs_path(@machine, install_id: @install.id)
    assert_redirected_to new_session_path
  end

  # The point of the whole thing: looking writes nothing. Not an Event, not a
  # projection onto the machine's columns (decisions/a-sample-is-not-an-act.md).
  test "reading logs records nothing and changes nothing" do
    sign_in_as @user
    seen_before = @machine.last_seen_at

    with_fake_steward do |steward|
      steward.on(/logs/, data: { "ok" => true, "message" => "boot ok\nGET / 200" })
      assert_no_difference [ -> { Event.count }, -> { Install.count } ] do
        get machine_logs_path(@machine, install_id: @install.id)
      end
    end

    assert_response :success
    assert_select ".logs-body", /GET \/ 200/
    assert_equal seen_before.to_i, @machine.reload.last_seen_at.to_i
  end

  test "the box is asked for the app by name, with the tail requested" do
    sign_in_as @user

    with_fake_steward do |steward|
      steward.on(/logs/, data: { "ok" => true, "message" => "x" })
      get machine_logs_path(@machine, install_id: @install.id, tail: 1000)

      assert steward.issued?("logs web --tail 1000 --json")
    end
    assert_select ".logs-tail.on", text: "1000"
  end

  # An unknown tail is not an invitation to pull the whole log across an SSH
  # connection — it falls back to the default rather than to "everything".
  test "a tail that isn't one of the offered sizes falls back to the default" do
    sign_in_as @user

    with_fake_steward do |steward|
      steward.on(/logs/, data: { "ok" => true, "message" => "x" })
      get machine_logs_path(@machine, install_id: @install.id, tail: "999999")

      assert steward.issued?("logs web --tail 200 --json")
    end
  end

  # The box's own sentence, not our transport's JSON. `steward logs` on an app that
  # isn't running exits non-zero with {"code":"not_found","message":…}.
  test "a refusal from the box is shown in the box's words" do
    sign_in_as @user

    with_fake_steward do |steward|
      steward.on(/logs/, success: false,
                 stdout: { "code" => "not_found", "message" => 'no running app "web"' }.to_json)
      get machine_logs_path(@machine, install_id: @install.id)
    end

    assert_response :success
    assert_select ".empty", /no running app "web"/
    assert_select ".logs-body", 0
  end

  # Reading is observe; every verb on the page is operate. So an observe-only box
  # still shows its logs — that is the moment you most want to look.
  test "logs are readable on a box whose key cannot act" do
    sign_in_as @user
    @machine.update!(scope: "observe")

    with_fake_steward do |steward|
      steward.on(/logs/, data: { "ok" => true, "message" => "still readable" })
      get machine_logs_path(@machine, install_id: @install.id)
    end

    assert_response :success
    assert_select ".logs-body", /still readable/
  end

  test "an app that was never placed on this box says so instead of asking" do
    sign_in_as @user
    elsewhere = Machine.create!(name: "other", ssh_host: "10.0.0.3", scope: "operate",
                                ssh_private_key: "k")

    with_fake_steward do |steward|
      get machine_logs_path(elsewhere, install_id: @install.id)
      assert_empty steward.commands, "nothing should be asked of a box it does not run on"
    end

    assert_response :not_found
    assert_select ".empty", /isn't placed on other/
  end

  # A name that could carry a flag never reaches the command line. `Install` already
  # enforces the charset; this is the seam's own guard, and it is the difference
  # between a bug and a flag injection.
  test "a name outside the box's charset is refused at the seam" do
    result = Steward::Observe.logs(@machine, "web --tail 999 ; rm -rf /")

    refute result[:ok]
    assert_match(/not a valid app name/, result[:error])
  end
end
