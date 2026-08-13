class AddAppearanceToUsers < ActiveRecord::Migration[8.1]
  # Appearance is a personal preference, so it belongs to the user, not to
  # `Setting` (which is fleet policy). Stored here rather than in the browser so
  # there is one answer to "what theme is this" — the same rule the rest of the
  # app follows about mirrors that can quietly disagree.
  def change
    add_column :users, :theme, :string, null: false, default: "steward"
    add_column :users, :mode,  :string, null: false, default: "system"
  end
end
