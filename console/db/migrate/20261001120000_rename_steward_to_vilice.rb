# The console half of the steward → vilice rename (decisions/the-name-is-vilice.md).
# The box account is now `_vilice`, so a machine reached as `steward` is reached as
# `_vilice` once its box is reinstalled — and there is no in-place migration on the
# box, so there is no box left that answers to the old name.
class RenameStewardToVilice < ActiveRecord::Migration[8.1]
  def up
    rename_column :machines, :steward_version, :vilice_version
    execute "UPDATE machines SET ssh_user = '_vilice' WHERE ssh_user = 'steward'"

    change_column_default :users, :theme, from: "steward", to: "vilice"
    execute "UPDATE users SET theme = 'vilice' WHERE theme = 'steward'"
  end

  def down
    execute "UPDATE users SET theme = 'steward' WHERE theme = 'vilice'"
    change_column_default :users, :theme, from: "vilice", to: "steward"

    execute "UPDATE machines SET ssh_user = 'steward' WHERE ssh_user = '_vilice'"
    rename_column :machines, :vilice_version, :steward_version
  end
end
