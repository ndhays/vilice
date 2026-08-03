class CreateProjectMachines < ActiveRecord::Migration[8.1]
  def change
    create_table :project_machines do |t|
      t.references :project, null: false, foreign_key: true
      t.references :machine, null: false, foreign_key: true

      t.timestamps
    end
    add_index :project_machines, [ :project_id, :machine_id ], unique: true
  end
end
