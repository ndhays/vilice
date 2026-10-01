# Seeds dispatcher. Picks a scenario by name and loads it from db/seeds/.
#
#   bin/rails db:seed                      → empty (the default; just an operator)
#   SCENARIO=realistic  bin/rails db:seed  → the dev box + projects + activity
#   SCENARIO=all_clear  bin/rails db:seed  → a healthy fleet
#   SCENARIO=all_broken bin/rails db:seed  → everything wrong
#   SCENARIO=big_fleet  bin/rails db:seed  → a large fleet + long record
#
# Every scenario but `realistic` wipes domain data first (they're contradictory
# worlds) and leans on the fake-observe seam for health — boot with
# VILICE_FAKE_OBSERVE=1, or just use `bin/scenario <name>`, which sets the
# flags for you. See db/seeds/README.md.
require_relative "seeds/shared"

name = ENV.fetch("SCENARIO", "empty")
path = Rails.root.join("db/seeds/#{name}.rb")
abort "Unknown scenario: #{name.inspect}. Try: #{Dir[Rails.root.join('db/seeds/*.rb')].map { |f| File.basename(f, '.rb') }.reject { |n| n == 'shared' }.sort.join(', ')}" unless path.exist?

load path
