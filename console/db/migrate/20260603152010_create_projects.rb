class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :contact_name
      t.string :contact_email
      t.boolean :starred, null: false, default: false

      t.timestamps
    end
    add_index :projects, :name, unique: true
    add_index :projects, :starred
  end
end
