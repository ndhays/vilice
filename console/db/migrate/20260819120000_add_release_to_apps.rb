# A library app's release command — the argv Steward runs once from the new image
# before the new color starts (migrations are the case it exists for).
#
# It lives on the App because it is a property of the image, the way port and health
# are: `bin/rails db:migrate` belongs to "a Rails app", not to one placement of it.
# An install copies it into its own spec at create, so an install can override it and a
# later library edit never silently changes what a deployed app runs.
class AddReleaseToApps < ActiveRecord::Migration[8.1]
  def change
    add_column :apps, :release, :json, default: [], null: false
  end
end
