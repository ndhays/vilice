# Which machine this console runs on, and its app name there — so it can update itself
# from its Settings page (`vilice update`). Stored, not an env var: `update` changes only
# the image, so an env var could not be set without the full deploy this replaces.
class AddSelfToSettings < ActiveRecord::Migration[8.1]
  def change
    add_reference :settings, :self_machine, foreign_key: { to_table: :machines, on_delete: :nullify }
    add_column :settings, :self_app_name, :string, default: "console", null: false
  end
end
