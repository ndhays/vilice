require "test_helper"

# The sharing allowlist (sharing = list): which projects, besides the owner, may
# pick up a box. Each add/remove is a recorded own-record act. machine-ownership.md.
class MachineGrantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @owner   = Project.create!(name: "Owner")
    @guest   = Project.create!(name: "Guest")
    @machine = Machine.create!(name: "box", ssh_host: "x", owner: @owner, sharing: "list")
    sign_in_as @user
  end

  test "allowing a project records it and lets that project attach" do
    assert_difference [ -> { MachineGrant.count }, -> { Event.count } ], 1 do
      post machine_grants_path(@machine), params: { project_id: @guest.id }
    end
    assert @machine.reload.permits?(@guest)
    assert_equal "shared machine", Event.latest.first.action
    assert ProjectMachine.new(project: @guest, machine: @machine).valid?
  end

  test "removing a grant records it and revokes the permission" do
    grant = MachineGrant.create!(machine: @machine, project: @guest)

    assert_difference -> { MachineGrant.count }, -1 do
      assert_difference -> { Event.count }, 1 do
        delete machine_grant_path(@machine, grant)
      end
    end
    refute @machine.reload.permits?(@guest)
    assert_equal "unshared machine", Event.latest.first.action
  end
end
