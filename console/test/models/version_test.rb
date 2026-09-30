require "test_helper"

class VersionTest < ActiveSupport::TestCase
  setup { @app_template = AppTemplate.create!(name: "web") }

  test "tag and image are required; tag is unique per app" do
    @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:9d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79")
    assert_not @app_template.versions.new(tag: "v1", image: "ghcr.io/acme/app@sha256:9d729d729d729d729d729d729d729d729d729d729d729d729d729d729d729d72").valid?  # dup tag
    assert_not @app_template.versions.new(image: "ghcr.io/acme/app@sha256:9d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79").valid?              # no tag
    assert_not @app_template.versions.new(tag: "v2").valid?                 # no image
    other = AppTemplate.create!(name: "other")
    assert other.versions.new(tag: "v1", image: "ghcr.io/acme/app@sha256:9d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79d79").valid?      # same tag, other app
  end

  test "newest_first orders by recency" do
    a = @app_template.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:9191919191919191919191919191919191919191919191919191919191919191", created_at: 2.days.ago)
    b = @app_template.versions.create!(tag: "v2", image: "ghcr.io/acme/app@sha256:9292929292929292929292929292929292929292929292929292929292929292", created_at: 1.day.ago)
    assert_equal [ b, a ], @app_template.versions.newest_first.to_a
  end

  # The box refuses an unpinned image (steward/internal/app/deploy.go), so a floating
  # tag in the library is a release that looks installable and is rejected at the far
  # end — after someone has built a placement on it. These mirror `validDigestPin`.
  test "an image must be digest-pinned, and the reason says why" do
    v = @app_template.versions.new(tag: "v9", image: "ghcr.io/acme/app:latest")
    assert_not v.valid?
    assert_match(/digest-pinned/, v.errors[:image].to_sentence)
    assert_match(/means something different tomorrow/, v.errors[:image].to_sentence)
  end

  test "a doubled prefix is caught, and the message hands back the fix" do
    v = @app_template.versions.new(tag: "v9", image: "ghcr.io/acme/app@sha256:sha256:#{'a' * 64}")
    assert_not v.valid?
    assert_match(/doubled/, v.errors[:image].to_sentence)
    assert_match(/@sha256:#{'a' * 64}/, v.errors[:image].to_sentence)
  end

  test "a digest of the wrong length or with non-hex characters is refused" do
    short = @app_template.versions.new(tag: "v9", image: "ghcr.io/acme/app@sha256:abc")
    assert_not short.valid?
    assert_match(/64 hex characters, got 3/, short.errors[:image].to_sentence)

    bad = @app_template.versions.new(tag: "v9", image: "ghcr.io/acme/app@sha256:#{'z' * 64}")
    assert_not bad.valid?
    assert_match(/non-hex/, bad.errors[:image].to_sentence)
  end

  test "a properly pinned image passes" do
    assert @app_template.versions.new(tag: "v9", image: "ghcr.io/acme/app@sha256:#{'ab' * 32}").valid?
  end
end
