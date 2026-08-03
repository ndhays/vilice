class AddAppToInstalls < ActiveRecord::Migration[8.1]
  def change
    # Nullable: nil = a custom image (slice 2b), and existing installs have no App.
    add_reference :installs, :app, null: true, foreign_key: true
  end
end
