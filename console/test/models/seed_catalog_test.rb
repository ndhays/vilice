require "test_helper"

# The seeded App Library is the only thing that exercises the catalog end to end, and
# nothing else did: every other test builds its own fixtures, so when `Version` learned
# to refuse an unpinned image the seeds kept shipping bare tags and `db:seed` broke for
# every scenario but `empty` — silently, because no test ever loaded them.
#
# Seed data has to obey the same rules as anything typed into the form. A catalog the
# app would refuse to save is not a rehearsal of the app, it is a fixture pretending
# to be one.
class SeedCatalogTest < ActiveSupport::TestCase
  setup { require Rails.root.join("db/seeds/shared").to_s }

  test "the seeded library saves — every release pinned, the way the box demands" do
    assert_nothing_raised { Scenario.library! }

    versions = Version.all.to_a
    assert_operator versions.size, :>, 5, "the catalog should cover the app form's shapes"
    versions.each do |v|
      assert v.valid?, "#{v.tag}: #{v.errors.full_messages.to_sentence}"
      assert_includes v.image, "@sha256:", "#{v.tag} is not digest-pinned"
    end
  end

  # Reseeding must not drift: a digest derived from the ref is stable, a random one
  # would make every reseed a different world and every screenshot a different image.
  test "a demo pin is stable across reseeds and visibly not a real release" do
    pin = Scenario.demo_pin("docker.io/library/redis")

    assert_equal pin, Scenario.demo_pin("docker.io/library/redis")
    assert_match(/\Adocker\.io\/library\/redis@sha256:5eed[0-9a-f]{60}\z/, pin)
  end
end
