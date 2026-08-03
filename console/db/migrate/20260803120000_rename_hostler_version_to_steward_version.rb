# The console half of the hostler → steward rename (decisions/the-names-are-steward.md).
#
# The on-box rename needs no migration — a box is reinstalled and its state is
# recreated. A console database is not: it is the operator's own records, it survives
# the upgrade, and it has to be carried across rather than rebuilt.
class RenameHostlerVersionToStewardVersion < ActiveRecord::Migration[8.1]
  def change
    rename_column :machines, :hostler_version, :steward_version
  end
end
