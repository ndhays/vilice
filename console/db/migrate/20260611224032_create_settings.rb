class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    # A singleton row of fleet-wide policy. The default matches slice-2a behavior:
    # installs come from the App Library unless the operator opts out.
    create_table :settings do |t|
      t.boolean :installs_library_only, default: true, null: false

      t.timestamps
    end
  end
end
