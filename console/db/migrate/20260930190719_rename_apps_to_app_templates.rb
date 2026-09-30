# An App Library entry is an App Template: what the page calls it, and what frees the
# name `App` for the thing an operator means by "the app" (today's Install).
class RenameAppsToAppTemplates < ActiveRecord::Migration[8.1]
  def change
    rename_table :apps, :app_templates
    rename_column :versions, :app_id, :app_template_id
    rename_column :installs, :app_id, :app_template_id

    # Labels on a template are polymorphic and name the class they hang off.
    reversible do |dir|
      dir.up   { execute "UPDATE labels SET labelable_type = 'AppTemplate' WHERE labelable_type = 'App'" }
      dir.down { execute "UPDATE labels SET labelable_type = 'App' WHERE labelable_type = 'AppTemplate'" }
    end
  end
end
