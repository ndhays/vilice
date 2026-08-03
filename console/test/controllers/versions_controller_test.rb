require "test_helper"

# Releases of a library App — add / promote / remove, each recorded.
class VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app  = App.create!(name: "web")
  end

  test "the first version is made latest and recorded" do
    sign_in_as @user
    assert_difference [ -> { Version.count }, -> { Event.count } ], 1 do
      post app_versions_path(@app), params: { version: { tag: "v1", image: "img@sha256:1" } }
    end
    assert_redirected_to @app
    assert_equal "v1", @app.reload.latest_version&.tag
    assert_equal "added version", Event.latest.first.action
  end

  test "make latest flips the flag to exactly one, recorded" do
    sign_in_as @user
    v1 = @app.versions.create!(tag: "v1", image: "i1"); @app.set_latest!(v1)
    v2 = @app.versions.create!(tag: "v2", image: "i2")
    assert_difference -> { Event.count }, 1 do
      patch latest_app_version_path(@app, v2)
    end
    assert_equal v2, @app.reload.latest_version
    assert_equal 1, @app.versions.where(latest: true).count
  end

  test "a non-first version with make_latest off does not steal latest" do
    sign_in_as @user
    v1 = @app.versions.create!(tag: "v1", image: "i1"); @app.set_latest!(v1)
    post app_versions_path(@app), params: { version: { tag: "v2", image: "i2" }, make_latest: "0" }
    assert_equal v1, @app.reload.latest_version
  end

  test "removing a version is recorded" do
    sign_in_as @user
    v = @app.versions.create!(tag: "v1", image: "i1")
    assert_difference -> { Version.count }, -1 do
      assert_difference -> { Event.count }, 1 do
        delete app_version_path(@app, v)
      end
    end
    assert_equal "removed version", Event.latest.first.action
  end
end
