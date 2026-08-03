class CreateSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :snapshots do |t|
      t.references :machine, null: false, foreign_key: true
      t.datetime :captured_at, null: false
      t.boolean :reachable, null: false, default: false
      t.json :metrics, null: false, default: {}   # load / mem / disk
      t.json :raw, null: false, default: {}        # the full Steward status sample

      t.timestamps
    end
    add_index :snapshots, [ :machine_id, :captured_at ]
  end
end
