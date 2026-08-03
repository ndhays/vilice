class CreateInstalls < ActiveRecord::Migration[8.1]
  def change
    create_table :installs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :image          # digest-pinned image reference
      t.string :hostname
      t.integer :port
      t.string :health         # health-check path Steward probes on deploy
      t.json :config, null: false, default: {}

      t.timestamps
    end
    add_index :installs, [ :project_id, :name ], unique: true
  end
end
