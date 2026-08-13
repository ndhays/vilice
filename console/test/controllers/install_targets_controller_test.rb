require "test_helper"

# Closing a placement gap is an **act**, never a background convergence
# (decisions/drift-is-surfaced-never-closed.md). A person picks a box, the placement is
# recorded, and the deploy that follows is the same witnessed ceremony as any other.
class InstallTargetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @project = Project.create!(name: "Acme")
    @install = @project.installs.create!(name: "web", image: "img@sha256:abc",
                                        count: 3, exposure: "balanced")
    @first   = operate_box("b1")
    @free    = operate_box("b2")
    @install.install_targets.create!(machine: @first, status: "running")
  end

  test "placing on another box is behind the login" do
    get new_install_target_path(@install)
    assert_redirected_to new_session_path
  end

  # The page states the gap it exists to close, and offers only boxes that could take it.
  test "the picker states the gap and omits boxes already running the install" do
    sign_in_as @user
    get new_install_target_path(@install)
    assert_response :success
    assert_select ".intent-line", /asked for 3 boxes/
    assert_select ".intent-line", /serving 1/
    assert_select "select[name=machine_id] option", text: "b2"
    assert_select "select[name=machine_id] option", { text: "b1", count: 0 }
  end

  # An observe key cannot deploy, so a box holding one is not a placement candidate.
  test "observe-scoped boxes are not offered" do
    sign_in_as @user
    Machine.create!(name: "eyes", ssh_host: "10.9.9.9", scope: "observe", ssh_private_key: "k")
    get new_install_target_path(@install)
    assert_select "select[name=machine_id] option", { text: "eyes", count: 0 }
  end

  test "placing records the act, then hands off to the witnessed deploy" do
    sign_in_as @user
    assert_difference [ -> { InstallTarget.count }, -> { Event.count } ], 1 do
      post install_targets_path(@install), params: { machine_id: @free.id }
    end
    event = Event.latest.first
    assert_equal "placed", event.action
    assert_equal "web on b2", event.summary
    assert_equal @user.email_address, event.actor
    # The new target is placed, not yet serving — the deploy is a separate, witnessed act.
    assert_equal "pending", InstallTarget.last.status
    assert_redirected_to new_machine_mutation_path(@free, act: "deploy",
                                                  install_id: @install.id, from: "install")
  end

  # The gap narrows only once the box actually serves — placing alone doesn't close it,
  # which is the whole distinction between intention and reality.
  test "placing does not by itself close the gap" do
    sign_in_as @user
    post install_targets_path(@install), params: { machine_id: @free.id }
    assert_equal(-2, @install.reload.placement_gap, "still 1 serving, not 2")
  end

  test "a box that is not a candidate is refused" do
    sign_in_as @user
    assert_no_difference [ -> { InstallTarget.count }, -> { Event.count } ] do
      post install_targets_path(@install), params: { machine_id: @first.id }  # already on it
    end
    assert_response :unprocessable_entity
  end

  test "no box picked is refused rather than guessed at" do
    sign_in_as @user
    assert_no_difference -> { InstallTarget.count } do
      post install_targets_path(@install), params: {}
    end
    assert_response :unprocessable_entity
  end

  # The per-machine name guard still has the last word — the picker narrows, it doesn't
  # replace the constraint.
  test "a name collision on the target box rolls the placement back" do
    sign_in_as @user
    other = Project.create!(name: "Other")
    other.installs.create!(name: "web", image: "img@sha256:def")
         .install_targets.create!(machine: @free, status: "running")

    assert_no_difference [ -> { InstallTarget.count }, -> { Event.count } ] do
      post install_targets_path(@install), params: { machine_id: @free.id }
    end
    assert_response :unprocessable_entity
  end

  # There is no scale-down action here on purpose: taking an app off a box is `remove`,
  # a verb that already exists and is already witnessed.
  test "there is no route for removing a placement here" do
    helpers = Rails.application.routes.url_helpers
    assert_not helpers.respond_to?(:install_target_path), "no show/destroy member route"
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/installs/#{@install.id}/targets/1",
                                              method: :delete)
    end
  end

  private

  def operate_box(name)
    Machine.create!(name: name, ssh_host: "10.0.0.#{name[-1]}", scope: "operate",
                    ssh_private_key: "k", status: "reachable", owner: @project).tap do |m|
      ProjectMachine.create!(project: @project, machine: m)
    end
  end
end
