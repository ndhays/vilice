# Invert `Install → Project` (decisions/console-layers.md). Tenancy is the outermost,
# most optional ring, so placement must not depend on it: you can't be made to invent a
# client before you can place an app. The constraint that actually matters was never
# here — `InstallTarget` enforces name and hostname uniqueness *on the box*, which is
# where a collision does damage. The per-project name index only ever protected a
# namespace nobody shares.
class MakeInstallProjectOptional < ActiveRecord::Migration[8.1]
  def change
    # A projectless install is a placement with no tenant — the homelab case.
    change_column_null :installs, :project_id, true

    # Names are unique per *machine* (InstallTarget), not per project. Two projects
    # may both run an `api`; the same box may not run two.
    remove_index :installs, column: %i[project_id name], unique: true
  end
end
