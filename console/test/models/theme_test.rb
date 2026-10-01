require "test_helper"

# Appearance is per-operator, and the registry is the only place a theme name is
# declared. The layout renders whatever it returns straight onto <html>, so an
# unknown name must never survive that far.
class ThemeTest < ActiveSupport::TestCase
  test "the default theme is vilice, and it carries both modes" do
    assert_equal "vilice", Theme::DEFAULT.name
    assert_includes Theme.names, "vilice"
    assert_equal %w[ system light dark ], Theme::MODES
  end

  test "an unknown or missing name falls back to the default rather than raising" do
    assert_equal Theme::DEFAULT, Theme.find("no-such-theme")
    assert_equal Theme::DEFAULT, Theme.find(nil)
    assert_equal "vilice", Theme.find("vilice").name
  end

  test "every theme has a label and a blurb for the Settings dropdown" do
    Theme::ALL.each do |t|
      assert t.label.present?, "#{t.name} has no label"
      assert t.blurb.present?, "#{t.name} has no blurb"
    end
  end

  test "a user defaults to the default theme following their system" do
    user = User.create!(email_address: "appearance@console.test", password: "password")
    assert_equal "vilice", user.theme
    assert_equal "system", user.mode
  end

  test "a theme or mode outside the registry is refused" do
    user = User.create!(email_address: "picky@console.test", password: "password")
    refute user.update(theme: "switchyard")
    refute user.update(mode: "sepia")
    assert_equal "vilice", user.reload.theme
  end
end
