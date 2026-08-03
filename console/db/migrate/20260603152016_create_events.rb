class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      # An event may attach to any of these; all optional.
      t.references :machine, foreign_key: true
      t.references :install, foreign_key: true
      t.references :project, foreign_key: true

      t.datetime :at, null: false
      t.string :actor, null: false      # the named actor from Steward's record (or a Steward Console user)
      t.string :action, null: false     # past-tense fact: "deployed", "rolled_back", "observed"
      t.string :summary
      t.json :raw, null: false, default: {}

      t.timestamps
    end
    add_index :events, :at
  end
end
