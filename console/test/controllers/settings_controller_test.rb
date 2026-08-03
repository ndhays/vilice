require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "installs are library-only by default" do
    assert Setting.current.installs_library_only
  end

  test "toggling the policy persists and is recorded" do
    sign_in_as @user
    assert_difference -> { Event.count }, 1 do
      patch settings_path, params: { setting: { installs_library_only: "0" } }
    end
    assert_redirected_to settings_path
    assert_not Setting.current.installs_library_only
    assert_equal "changed settings", Event.latest.first.action
  end

  test "change password with the correct current password" do
    sign_in_as @user
    assert_changes -> { @user.reload.password_digest } do
      patch settings_password_path, params: {
        current_password: "password", password: "newsecret", password_confirmation: "newsecret"
      }
    end
    assert_redirected_to settings_path
  end

  test "change password rejects a wrong current password" do
    sign_in_as @user
    assert_no_changes -> { @user.reload.password_digest } do
      patch settings_password_path, params: {
        current_password: "wrong", password: "newsecret", password_confirmation: "newsecret"
      }
    end
    assert_redirected_to settings_path
    follow_redirect!
    assert_select "div", /Current password is incorrect/
  end

  test "change password rejects a mismatched confirmation" do
    sign_in_as @user
    assert_no_changes -> { @user.reload.password_digest } do
      patch settings_password_path, params: {
        current_password: "password", password: "newsecret", password_confirmation: "different"
      }
    end
    assert_redirected_to settings_path
  end

  test "erase all data wipes the fleet but keeps the login and settings" do
    sign_in_as @user
    Setting.current  # materialize the singleton so "survives" is meaningful
    project = Project.create!(name: "Doomed")
    machine = Machine.create!(name: "m1", ssh_host: "10.0.0.1")
    Install.create!(project: project, name: "web", image: "img@sha256:abc")
           .install_targets.create!(machine: machine)
    Event.record!(actor: @user.email_address, action: "added install", summary: "x")

    delete settings_data_path
    assert_redirected_to settings_path

    [ Project, Machine, Install, InstallTarget, Event ].each do |model|
      assert_equal 0, model.count, "#{model} should be empty"
    end
    assert User.exists?(@user.id), "the operator's login survives"
    assert Setting.exists?, "the Setting survives"
  end
end
