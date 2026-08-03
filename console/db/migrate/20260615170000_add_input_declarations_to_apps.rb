# Graduate App.env from a {KEY => value} bag to an input *schema* — a list of
# { key, secret } entries — and add secret_files (mounted file secrets). The library
# declares what an app *needs* (names only); values are supplied at install, off-record
# for secrets. See decisions/open/app-library.md.
class AddInputDeclarationsToApps < ActiveRecord::Migration[8.1]
  def up
    add_column :apps, :secret_files, :json, default: [], null: false
    change_column_default :apps, :env, from: {}, to: []

    # Convert any existing bag to the list shape (names only — values leave the library).
    app = Class.new(ActiveRecord::Base) { self.table_name = "apps" }
    app.reset_column_information
    app.find_each do |a|
      list = case a.env
             when Hash  then a.env.keys.map { |k| { "key" => k, "secret" => false } }
             when Array then a.env
             else []
             end
      a.update_columns(env: list)
    end
  end

  def down
    change_column_default :apps, :env, from: [], to: {}
    remove_column :apps, :secret_files
  end
end
