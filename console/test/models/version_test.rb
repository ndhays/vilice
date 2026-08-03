require "test_helper"

class VersionTest < ActiveSupport::TestCase
  setup { @app = App.create!(name: "web") }

  test "tag and image are required; tag is unique per app" do
    @app.versions.create!(tag: "v1", image: "img")
    assert_not @app.versions.new(tag: "v1", image: "img2").valid?  # dup tag
    assert_not @app.versions.new(image: "img").valid?              # no tag
    assert_not @app.versions.new(tag: "v2").valid?                 # no image
    other = App.create!(name: "other")
    assert other.versions.new(tag: "v1", image: "img").valid?      # same tag, other app
  end

  test "newest_first orders by recency" do
    a = @app.versions.create!(tag: "v1", image: "i1", created_at: 2.days.ago)
    b = @app.versions.create!(tag: "v2", image: "i2", created_at: 1.day.ago)
    assert_equal [ b, a ], @app.versions.newest_first.to_a
  end
end
