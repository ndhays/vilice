# The containers an app needs on the same box and that nothing else may reach — a
# database, a cache. Declared on the App because they are part of what the image is,
# the way port, health and the release command are; an Install copies them at create so
# a later library edit never silently changes what an already-placed app runs.
#
# Shape matches the box's spec exactly (steward/internal/app/accessory.go):
#   { "name", "image", "env" => {}, "secrets" => [], "volumes" => [] }
class AddAccessoriesToApps < ActiveRecord::Migration[8.1]
  def change
    add_column :apps, :accessories, :json, default: [], null: false
  end
end
