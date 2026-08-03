class CreateApps < ActiveRecord::Migration[8.1]
  def change
    create_table :apps do |t|
      t.string :name, null: false
      t.string :image
      t.integer :port
      t.string :health
      t.string :description
      # env defaults for the install flow (slice 2); empty for now.
      t.json :env, default: {}, null: false

      t.timestamps
    end
    add_index :apps, :name, unique: true
  end
end
