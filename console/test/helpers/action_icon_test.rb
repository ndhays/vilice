require "test_helper"

# `icon()` renders an empty string for a name it doesn't know, so a typo in the
# action → glyph mapping is invisible: the entry just loses its glyph and nothing
# fails. These pin the mapping instead.
class ActionIconTest < ActionView::TestCase
  include ApplicationHelper
  include IconHelper

  # Every verb the app can write to the record — the witnessed acts from the
  # ceremony's allowlist, plus the console's own-record verbs — must draw. All one
  # word, so the Record's filter pills stay short (blueprint/console/interface.md).
  CONSOLE_VERBS = %w[
    added removed edited set placed restated granted revoked transferred released
    promoted demoted starred unstarred imported opened restricted authorized linked
    observed
  ].freeze

  # A verb is one word — the object it acted on belongs in the summary beside it,
  # not in the action column, where it only made the filter pills longer.
  test "every verb is a single word" do
    (Mutation::ACTS.values.map(&:past) + CONSOLE_VERBS).each do |verb|
      # "rolled back" is the one exception: English has no one-word past tense for it.
      next if verb == "rolled back"
      assert_equal 1, verb.split.size, "#{verb.inspect} is more than one word"
    end
  end

  test "every verb the app can write maps to a glyph that exists" do
    verbs = Mutation::ACTS.values.map(&:past) + CONSOLE_VERBS
    verbs.each do |verb|
      name = action_icon_name(verb)
      assert IconHelper::ICONS.key?(name),
             "#{verb.inspect} maps to #{name.inspect}, which is not in ICONS"
      assert icon(name).present?, "#{name.inspect} rendered empty"
    end
  end

  test "the single-word verbs draw what they mean" do
    assert_equal "check-check", action_icon_name("updated")
    assert_equal "key-round",   action_icon_name("authorized")
    assert_equal "link",        action_icon_name("linked")
    assert_equal "rocket",      action_icon_name("deployed")
    assert_equal "play",        action_icon_name("restarted")
  end

  # The record is append-only: entries written before the verbs were shortened keep
  # their recorded wording, and must still draw the same glyph as their successors.
  test "the older two-word spellings still draw" do
    assert_equal "check-check", action_icon_name("applied updates")
    assert_equal "key-round",   action_icon_name("authorized client")
    assert_equal "link",        action_icon_name("linked machine")
  end

  # The verb is rendered on its own, so the detail beside it must not repeat it —
  # including for entries recorded before the two were kept apart.
  test "act_detail drops a verb the summary repeats" do
    item = ->(action, summary) { ChainItem.new(at: Time.current, actor: "a", action: action, summary: summary) }
    assert_equal "acme-web on devbox", act_detail(item.("deployed", "Deployed acme-web on devbox"))
    assert_equal "acme-web on devbox", act_detail(item.("deployed", "acme-web on devbox"))
    assert_equal "devbox",             act_detail(item.("applied updates", "applied updates devbox"))
    # An old two-word verb whose summary repeats only its first word.
    assert_equal "devbox to Acme",     act_detail(item.("linked machine", "Linked devbox to Acme"))
    # A summary that was only ever the verb leaves nothing, and the view omits it.
    assert_equal "", act_detail(item.("deployed", "deployed"))
    # A word that merely starts with the verb is not a repeat.
    assert_equal "addendum.txt", act_detail(item.("added", "addendum.txt"))
  end

  # An act and its outcome must not wear the same glyph — `circle-check` is the
  # settled-ok tick on an entry, so no verb may claim it.
  test "no verb borrows the outcome tick" do
    verbs = Mutation::ACTS.values.map(&:past) + CONSOLE_VERBS
    verbs.each do |verb|
      assert_not_equal "circle-check", action_icon_name(verb), "#{verb.inspect} took the outcome glyph"
    end
  end
end
