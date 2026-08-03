class CreateInstallTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :install_targets do |t|
      t.references :install, null: false, foreign_key: true
      t.references :machine, null: false, foreign_key: true

      # The old Dispatcher install decision points: one machine vs. a replica set.
      t.string :strategy, null: false, default: "single"
      t.integer :position, null: false, default: 0

      # What we asked Steward to run vs. what it reports running.
      t.string :desired_image
      t.string :current_image
      t.string :status, null: false, default: "pending"

      t.timestamps
    end
    add_index :install_targets, [ :install_id, :machine_id ], unique: true
  end
end
