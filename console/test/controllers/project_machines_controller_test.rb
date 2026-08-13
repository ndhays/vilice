require "test_helper"

# Attaching an existing fleet machine to a project — the M:N edge. The ProjectMachine
# join enforces the ownership guardrail: a box must permit the project (it owns it, or
# the box is shared with everyone / the project is on its allowlist). machine-ownership.md.
class ProjectMachinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @project = Project.create!(name: "Acme")
    # @project owns this box (the common case: you registered it for this client).
    @machine = Machine.create!(name: "box1", ssh_host: "10.0.0.1", scope: "operate", owner: @project)
    sign_in_as @user
  end

  test "attaches a box the project owns and records it" do
    assert_difference [ -> { ProjectMachine.count }, -> { Event.count } ], 1 do
      post project_project_machines_path(@project), params: { machine_id: @machine.id }
    end
    assert_includes @project.reload.machines, @machine
    assert_redirected_to project_path(@project)
    assert_equal "added", Event.latest.first.action
  end

  test "a dedicated box owned by another project is refused" do
    other = Project.create!(name: "Other")
    box = Machine.create!(name: "box2", ssh_host: "10.0.0.2", owner: other) # dedicated to Other

    assert_no_difference [ -> { ProjectMachine.count }, -> { Event.count } ] do
      post project_project_machines_path(@project), params: { machine_id: box.id }
    end
    refute_includes @project.reload.machines, box
    assert_redirected_to project_path(@project)
    assert_match(/isn't shared/i, flash[:alert])
  end

  test "a box shared with everyone can be picked up by another project" do
    other = Project.create!(name: "Other")
    box = Machine.create!(name: "box3", ssh_host: "10.0.0.3", owner: other, sharing: "everyone")

    assert_difference -> { ProjectMachine.count }, 1 do
      post project_project_machines_path(@project), params: { machine_id: box.id }
    end
    assert_includes @project.reload.machines, box
  end

  test "a list-shared box is refused without a grant, allowed with one" do
    other = Project.create!(name: "Other")
    box = Machine.create!(name: "box4", ssh_host: "10.0.0.4", owner: other, sharing: "list")

    assert_no_difference -> { ProjectMachine.count } do
      post project_project_machines_path(@project), params: { machine_id: box.id }
    end

    MachineGrant.create!(machine: box, project: @project)
    assert_difference -> { ProjectMachine.count }, 1 do
      post project_project_machines_path(@project), params: { machine_id: box.id }
    end
    assert_includes @project.reload.machines, box
  end
end
