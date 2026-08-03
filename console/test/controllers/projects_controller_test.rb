require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = Project.create!(name: "Acme")
    sign_in_as @user
  end

  test "index search filters by name (and drops the starred split)" do
    @project.update!(starred: true)
    other = Project.create!(name: "Globex")

    get projects_path(q: "Globex")
    assert_response :success
    assert_select ".rows .row-name", text: "Globex"
    assert_select ".rows .row-name", text: "Acme", count: 0
    assert_select ".starred-heading", count: 0   # search shows one flat list
  end

  test "create adds the project, records the act, and redirects" do
    assert_difference [ -> { Project.count }, -> { Event.count } ], 1 do
      post projects_path, params: { project: {
        name: "Globex", contact_name: "Hank Scorpio", contact_email: "hank@globex.test"
      } }
    end
    project = Project.find_by(name: "Globex")
    assert_equal "Hank Scorpio", project.contact_name
    e = Event.latest.first
    assert_equal @user.email_address, e.actor
    assert_equal "added project", e.action
    assert_redirected_to project_path(project)
  end

  test "create with a blank name re-renders and records nothing" do
    assert_no_difference [ -> { Project.count }, -> { Event.count } ] do
      post projects_path, params: { project: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update edits the project and records the act" do
    assert_difference -> { Event.count }, 1 do
      patch project_path(@project), params: { project: { name: "Acme Corp", contact_name: "Wile E." } }
    end
    @project.reload
    assert_equal "Acme Corp", @project.name
    assert_equal "Wile E.", @project.contact_name
    assert_equal "updated project", Event.latest.first.action
    assert_redirected_to project_path(@project)
  end

  test "update with a blank name re-renders" do
    patch project_path(@project), params: { project: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "Acme", @project.reload.name
  end

  test "destroy removes an empty project and keeps the record" do
    assert_difference -> { Project.count }, -1 do
      assert_difference -> { Event.count }, 1 do   # the "removed project" act survives (nullified)
        delete project_path(@project)
      end
    end
    assert_redirected_to projects_path
    assert_equal "removed project", Event.latest.first.action
  end

  test "destroy is refused while the project still runs a live app" do
    machine = Machine.create!(name: "box1", ssh_host: "10.0.0.1", scope: "operate", owner: @project)
    ProjectMachine.create!(project: @project, machine: machine)
    @project.installs.create!(name: "web", image: "img@sha256:abc")
            .install_targets.create!(machine: machine, status: "running")

    assert_no_difference -> { Project.count } do
      delete project_path(@project)
    end
    assert_redirected_to project_path(@project)
    follow_redirect!
    assert_select "div", /still has live installs/
  end

  test "destroy succeeds once the app is retired" do
    # A box @project uses but doesn't own (so ownership doesn't gate the delete —
    # this test is about the live-app guard).
    owner = Project.create!(name: "Owner")
    machine = Machine.create!(name: "box1", ssh_host: "10.0.0.1", scope: "operate",
                              owner: owner, sharing: "everyone")
    ProjectMachine.create!(project: @project, machine: machine)
    @project.installs.create!(name: "web", image: "img@sha256:abc")
            .install_targets.create!(machine: machine, status: "retired")

    assert_difference -> { Project.count }, -1 do
      delete project_path(@project)
    end
    assert_redirected_to projects_path
  end

  test "destroy is refused while the project still owns a box (transfer first)" do
    Machine.create!(name: "owned-box", ssh_host: "10.0.0.9", owner: @project)

    assert_no_difference -> { Project.count } do
      delete project_path(@project)
    end
    assert_redirected_to project_path(@project)
    follow_redirect!
    assert_select "div", /still owns owned-box/
  end

  test "star toggles and records the act, attributed to the operator" do
    assert_changes -> { @project.reload.starred? }, from: false, to: true do
      assert_difference -> { Event.count }, 1 do
        patch star_project_path(@project)
      end
    end
    e = Event.latest.first
    assert_equal @user.email_address, e.actor
    assert_equal "starred project", e.action

    # …and back off.
    patch star_project_path(@project)
    refute @project.reload.starred?
    assert_equal "unstarred project", Event.latest.first.action
  end
end
