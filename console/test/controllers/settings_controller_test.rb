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
    assert_equal "opened", Event.latest.first.action
  end

  # Appearance is personal, so it is not a recorded act — nothing about the fleet
  # changed and no box was touched.
  test "appearance saves theme and mode without writing to the record" do
    sign_in_as @user
    assert_no_difference -> { Event.count } do
      patch settings_appearance_path, params: { theme: "steward", mode: "dark" }
    end
    assert_equal "dark", @user.reload.mode
    assert_equal "steward", @user.theme
  end

  # The rail's toggle knows only the mode; it must not blank the theme by omission.
  test "the rail toggle sends mode alone and leaves the theme intact" do
    sign_in_as @user
    @user.update!(theme: "steward", mode: "light")
    patch settings_appearance_path, params: { mode: "dark" }
    assert_equal "dark", @user.reload.mode
    assert_equal "steward", @user.theme
  end

  test "an unknown theme is refused rather than reaching the layout" do
    sign_in_as @user
    patch settings_appearance_path, params: { theme: "switchyard" }
    assert_equal "steward", @user.reload.theme
  end

  # The theme is in the first byte — there is no stored copy in the browser that
  # could disagree, and nothing to flash on paint.
  test "the layout renders the operator's appearance onto <html>" do
    sign_in_as @user
    @user.update!(mode: "dark")
    get settings_path
    assert_response :success
    assert_select "html[data-theme=?][data-mode=?]", "steward", "dark"
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
    Install.create!(project: project, name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
           .install_targets.create!(machine: machine)
    Event.record!(actor: @user.email_address, action: "added", summary: "x")

    delete settings_data_path
    assert_redirected_to settings_path

    [ Project, Machine, Install, InstallTarget, Event ].each do |model|
      assert_equal 0, model.count, "#{model} should be empty"
    end
    assert User.exists?(@user.id), "the operator's login survives"
    assert Setting.exists?, "the Setting survives"
  end
end
