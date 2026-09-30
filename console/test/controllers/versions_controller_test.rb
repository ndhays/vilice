require "test_helper"

# Releases of a library App — add / promote / remove, each recorded.
class VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app_template  = AppTemplate.create!(name: "web")
  end

  test "the first version is made latest and recorded" do
    sign_in_as @user
    assert_difference [ -> { Version.count }, -> { Event.count } ], 1 do
      post app_template_versions_path(@app_template), params: { version: { tag: "v1", image: "img@sha256:1111111111111111111111111111111111111111111111111111111111111111" } }
    end
    assert_redirected_to @app_template
    assert_equal "v1", @app_template.reload.latest_version&.tag
    assert_equal "added", Event.latest.first.action
  end

  test "make latest flips the flag to exactly one, recorded" do
    sign_in_as @user
    v1 = @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:9191919191919191919191919191919191919191919191919191919191919191"); @app_template.set_latest!(v1)
    v2 = @app_template.versions.create!(tag: "v2", image: "ghcr.io/acme/app@sha256:9292929292929292929292929292929292929292929292929292929292929292")
    assert_difference -> { Event.count }, 1 do
      patch latest_app_template_version_path(@app_template, v2)
    end
    assert_equal v2, @app_template.reload.latest_version
    assert_equal 1, @app_template.versions.where(latest: true).count
  end

  test "a non-first version with make_latest off does not steal latest" do
    sign_in_as @user
    v1 = @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:9191919191919191919191919191919191919191919191919191919191919191"); @app_template.set_latest!(v1)
    post app_template_versions_path(@app_template), params: { version: { tag: "v2", image: "ghcr.io/acme/app@sha256:9292929292929292929292929292929292929292929292929292929292929292" }, make_latest: "0" }
    assert_equal v1, @app_template.reload.latest_version
  end

  test "removing a version is recorded" do
    sign_in_as @user
    v = @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:9191919191919191919191919191919191919191919191919191919191919191")
    assert_difference -> { Version.count }, -1 do
      assert_difference -> { Event.count }, 1 do
        delete app_template_version_path(@app_template, v)
      end
    end
    assert_equal "removed", Event.latest.first.action
  end

  # ── Looking a tag up ───────────────────────────────────────────────────────
  # The console can fill the digest in for you. It must not save it for you: resolution
  # is a read and pinning is a decision (app/services/registry.rb).
  test "resolving fills the field in and saves nothing" do
    sign_in_as @user
    digest = "sha256:#{'d' * 64}"

    assert_no_difference [ -> { Version.count }, -> { Event.count } ] do
      with_resolve(digest) do
        post resolve_app_template_versions_path(@app_template),
             params: { version: { tag: "v1", image: "ghcr.io/acme/web:v1" } }
      end
    end
    assert_response :success
    # The form comes back carrying the answer, ready for the press that does save it.
    assert_select "input[name=?][value=?]", "version[image]", "ghcr.io/acme/web@#{digest}"
    assert_select ".flash.notice", /Nothing is saved yet/
  end

  # A registry that wants a credential is the end of the road here, not a prompt for one:
  # registry logins live on the box (decisions/registry-credentials.md).
  test "a registry error is shown on the form, and still saves nothing" do
    sign_in_as @user

    assert_no_difference -> { Version.count } do
      with_resolve_error("ghcr.io wants a credential for acme/web.") do
        post resolve_app_template_versions_path(@app_template),
             params: { version: { tag: "v1", image: "ghcr.io/acme/web:v1" } }
      end
    end
    assert_response :success
    assert_select ".flash.alert", /wants a credential/
  end

  test "resolving is behind the login like everything else" do
    post resolve_app_template_versions_path(@app_template), params: { version: { tag: "v1", image: "nginx" } }
    assert_redirected_to new_session_path
  end

  private

  def with_resolve(digest)
    original = Registry.method(:resolve)
    Registry.define_singleton_method(:resolve) { |*| digest }
    yield
  ensure
    Registry.define_singleton_method(:resolve, original)
  end

  def with_resolve_error(message)
    original = Registry.method(:resolve)
    Registry.define_singleton_method(:resolve) { |*| raise Registry::Error, message }
    yield
  ensure
    Registry.define_singleton_method(:resolve, original)
  end
end
