# An Install is an App — what an operator means by "the app": a template configured and
# placed for a client — and one app on one box is a Placement, the word the pages and
# the docs already used for it. The template took the name AppTemplate first, which is
# what freed `apps`.
class RenameInstallsToApps < ActiveRecord::Migration[8.1]
  def change
    rename_table :installs, :apps
    rename_table :install_targets, :placements
    rename_column :placements, :install_id, :app_id
    rename_column :events, :install_id, :app_id
    rename_column :settings, :installs_library_only, :apps_library_only

    # Labels on an app are polymorphic and name the class they hang off.
    reversible do |dir|
      dir.up   { execute "UPDATE labels SET labelable_type = 'App' WHERE labelable_type = 'Install'" }
      dir.down { execute "UPDATE labels SET labelable_type = 'Install' WHERE labelable_type = 'App'" }
    end
  end
end
