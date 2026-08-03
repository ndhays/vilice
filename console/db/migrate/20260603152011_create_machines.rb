class CreateMachines < ActiveRecord::Migration[8.1]
  def change
    create_table :machines do |t|
      t.string :name, null: false

      # How Steward Console reaches the Steward box over scoped SSH.
      t.string :ssh_host, null: false
      t.integer :ssh_port, null: false, default: 22
      t.string :ssh_user, null: false, default: "root"

      # The scope granted to this machine's key on the box: observe ⊂ operate.
      t.string :scope, null: false, default: "observe"

      # Decision 2 — the SSH private key lives here, encrypted at rest
      # (Active Record Encryption). Per-machine keypair, so revoking one
      # box never touches another.
      t.text :ssh_private_key

      # Decision 1 — a machine serves one Project unless it opts into sharing.
      t.boolean :multi_tenant, null: false, default: false

      # Observe-side facts kept fresh from Steward's record.
      # Named `hostler_version` here because that is what this migration created in
      # June. The rename to `steward_version` is its own migration, further down —
      # editing history would give two databases built from the same repo at
      # different times different column names.
      t.string :hostler_version
      t.datetime :last_seen_at
      t.string :status, null: false, default: "unknown"

      t.timestamps
    end
    add_index :machines, :name, unique: true
  end
end
