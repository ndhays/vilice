# Machine ownership + the explicit sharing model
# (decisions/machine-ownership.md). A box gains an `owner` Project and a
# tri-state `sharing` (dedicated / everyone / list), replacing the blunt
# `multi_tenant` boolean. The `list` mode draws its allowlist from `machine_grants`.
class AddMachineOwnershipAndSharing < ActiveRecord::Migration[8.1]
  def up
    # Who owns the box. Nullable: a released/unclaimed box is unowned (surfaced on
    # the fleet page). Deleting an owning project is blocked in the app, never a
    # silent nullify — the FK is a backstop only.
    add_reference :machines, :owner, foreign_key: { to_table: :projects }, null: true

    # The explicit sharing mode. Default dedicated (owner only) — never wide open
    # by accident.
    add_column :machines, :sharing, :string, null: false, default: "dedicated"

    # Carry the old boolean forward: a shared box becomes "everyone" (its prior
    # meaning — any project could attach). Operators narrow it to "list" by hand.
    execute "UPDATE machines SET sharing = 'everyone' WHERE multi_tenant = 1"

    remove_column :machines, :multi_tenant

    # The allowlist for `sharing = list`: the projects (besides the owner) a box
    # will accept. Owner-managed; a recorded act.
    create_table :machine_grants do |t|
      t.references :machine, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.timestamps
    end
    add_index :machine_grants, %i[machine_id project_id], unique: true
  end

  def down
    drop_table :machine_grants
    add_column :machines, :multi_tenant, :boolean, null: false, default: false
    execute "UPDATE machines SET multi_tenant = 1 WHERE sharing IN ('everyone', 'list')"
    remove_column :machines, :sharing
    remove_reference :machines, :owner
  end
end
