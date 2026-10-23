require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "apps are library-only by default" do
    assert Setting.current.apps_library_only
  end

  test "toggling the policy persists and is recorded" do
    sign_in_as @user
    assert_difference -> { Event.count }, 1 do
      patch settings_path, params: { setting: { apps_library_only: "0" } }
    end
    assert_redirected_to settings_path
    assert_not Setting.current.apps_library_only
    assert_equal "opened", Event.latest.first.action
  end

  # Appearance is personal, so it is not a recorded act — nothing about the fleet
  # changed and no box was touched.
  test "appearance saves theme and mode without writing to the record" do
    sign_in_as @user
    assert_no_difference -> { Event.count } do
      patch settings_appearance_path, params: { theme: "vilice", mode: "dark" }
    end
    assert_equal "dark", @user.reload.mode
    assert_equal "vilice", @user.theme
  end

  # The rail's toggle knows only the mode; it must not blank the theme by omission.
  test "the rail toggle sends mode alone and leaves the theme intact" do
    sign_in_as @user
    @user.update!(theme: "vilice", mode: "light")
    patch settings_appearance_path, params: { mode: "dark" }
    assert_equal "dark", @user.reload.mode
    assert_equal "vilice", @user.theme
  end

  test "an unknown theme is refused rather than reaching the layout" do
    sign_in_as @user
    patch settings_appearance_path, params: { theme: "switchyard" }
    assert_equal "vilice", @user.reload.theme
  end

  # The theme is in the first byte — there is no stored copy in the browser that
  # could disagree, and nothing to flash on paint.
  test "the layout renders the operator's appearance onto <html>" do
    sign_in_as @user
    @user.update!(mode: "dark")
    get settings_path
    assert_response :success
    assert_select "html[data-theme=?][data-mode=?]", "vilice", "dark"
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
    App.create!(project: project, name: "web", image: "img@sha256:abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca")
           .placements.create!(machine: machine)
    Event.record!(actor: @user.email_address, action: "added", summary: "x")

    delete settings_data_path
    assert_redirected_to settings_path

    [ Project, Machine, App, Placement, Event ].each do |model|
      assert_equal 0, model.count, "#{model} should be empty"
    end
    assert User.exists?(@user.id), "the operator's login survives"
    assert Setting.exists?, "the Setting survives"
  end

  # Every card on this page keeps its own Save. The fleet-policy card's used to sit
  # loose beneath it — a leftover from when one form spanned several cards — which left
  # no gap at all between it and the card following.
  test "each settings card carries its own action, inside the card" do
    sign_in_as @user
    get settings_path
    assert_response :success
    assert_select ".card.setting form .card-actions button", /Save Settings/
    assert_select ".card.setting.appearance form .card-actions button", /Save Appearance/
    assert_select ".card.setting.account form .card-actions button", /Change Password/
    # Nothing is left loose between the cards.
    assert_select "body > form", count: 0
  end

  # ── This console, updating itself (decisions/update-is-rollback-pointed-forward.md) ──
  NEW_IMAGE = "zot.example.com/vilice-console@sha256:#{'b' * 64}".freeze

  def self_box
    Machine.create!(name: "home", ssh_host: "10.0.0.5", scope: "operate", ssh_private_key: "k")
  end

  def box_reports(apps)
    { status: { ok: true, data: { "data" => { "apps" => apps } } } }
  end

  test "with no machine chosen, the card says what it needs and offers no update" do
    sign_in_as @user
    stub_observe { get settings_path }
    assert_select "#this-console", /say which machine it runs on/
    assert_select "form[action=?]", settings_update_console_path, count: 0
  end

  test "choosing where this console runs is recorded" do
    sign_in_as @user
    box = self_box
    assert_difference -> { Event.count }, 1 do
      patch settings_self_path, params: { self_machine_id: box.id, self_app_name: "console" }
    end
    assert_equal box, Setting.current.self_machine
    assert_match(/this console runs as console on home/, Event.latest.first.summary)
  end

  test "a bad app name is refused, not saved" do
    sign_in_as @user
    patch settings_self_path, params: { self_machine_id: self_box.id, self_app_name: "-x" }
    assert_nil Setting.current.reload.self_machine
    assert flash[:alert].present?
  end

  test "the card shows what the box runs, and how the last update went" do
    sign_in_as @user
    Setting.current.update!(self_machine: self_box)
    apps = [ { "name" => "console", "image" => "zot.example.com/vilice-console@sha256:#{'a' * 64}",
               "update" => { "state" => "failed", "image" => NEW_IMAGE, "message" => "health check failed, old app left running" } } ]
    stub_observe(**box_reports(apps)) { get settings_path }
    assert_select "#this-console form[action=?]", settings_update_console_path
    assert_select "#this-console", /failed/
    assert_select "#this-console", /old app left running/
    assert_select "#this-console .cmd-block pre.cmd", "vilice update console --image <image>"
  end

  test "updating sends `update` with the image and nothing else, and records it" do
    sign_in_as @user
    Setting.current.update!(self_machine: self_box)
    with_fake_vilice do |vilice|
      vilice.on(/^update /, data: { "code" => "ok", "message" => "updating" })
      assert_difference -> { Event.where(action: "updated").count }, 1 do
        post settings_update_console_path, params: { image: NEW_IMAGE }
      end
      assert vilice.issued?("update console --image #{NEW_IMAGE} --json")
      assert_nil vilice.stdin_for(/^update /), "no secret, nothing on stdin"
    end
    assert_redirected_to settings_path(anchor: "this-console")
    assert_match(/Updating/, flash[:notice])
  end

  test "an update needs a machine, and a pinned image" do
    sign_in_as @user
    post settings_update_console_path, params: { image: NEW_IMAGE }
    assert_match(/Choose the machine/, flash[:alert])

    Setting.current.update!(self_machine: self_box)
    assert_no_difference -> { Event.count } do
      post settings_update_console_path, params: { image: "zot.example.com/vilice-console:latest" }
      post settings_update_console_path, params: { image: "#{NEW_IMAGE} --json; rm" }
    end
    assert_match(/pinned by digest/, flash[:alert])
  end
end
