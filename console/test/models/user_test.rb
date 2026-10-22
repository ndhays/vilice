require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  # A deployed console's first user comes from the deploy, and only the first: a value
  # left in the spec must never reset a password or add an account on a later boot.
  test "create_first makes the first user, and only ever the first" do
    User.delete_all
    assert_nil User.create_first("", "secret-pass"), "no email, no user"
    assert_nil User.create_first("a@example.com", nil), "no password, no user"

    first = User.create_first("Admin@Example.com", "secret-pass")
    assert first.authenticate("secret-pass")
    assert_equal "admin@example.com", first.email_address

    assert_nil User.create_first("other@example.com", "x"), "a second call does nothing"
    assert_nil User.create_first("admin@example.com", "changed"), "and cannot reset the password"
    assert_equal 1, User.count
    assert first.reload.authenticate("secret-pass")
  end

  # The scenarios sign in as operator@console.test / password. Seeds run on a new
  # production database, so that account must refuse to exist anywhere but dev and test.
  test "the seeded operator refuses outside dev and test" do
    require Rails.root.join("db/seeds/shared").to_s
    stub_returning(Rails, :env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(RuntimeError) { Scenario.operator! }
    end
  end
end
