class CreateLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :labels do |t|
      t.references :labelable, polymorphic: true, null: false
      t.string :key, null: false
      t.string :value   # optional — Hetzner-style: a bare key is valid

      t.timestamps
    end

    # A resource carries a given key at most once (key/value, not key/many).
    add_index :labels, [ :labelable_type, :labelable_id, :key ], unique: true,
              name: "index_labels_on_labelable_and_key"
    # Cheap lookups for label-based search across the fleet.
    add_index :labels, [ :key, :value ]
  end
end
