class CreateVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :versions do |t|
      t.references :app, null: false, foreign_key: true
      t.string :tag, null: false       # human handle, e.g. "v1.2.0"
      t.string :image, null: false     # the digest-pinned image for this release
      t.boolean :latest, default: false, null: false

      t.timestamps
    end
    add_index :versions, [ :app_id, :tag ], unique: true
    # Exactly one latest version per app, enforced at the DB.
    add_index :versions, :app_id, unique: true, where: "latest", name: "index_versions_one_latest_per_app"
  end
end
