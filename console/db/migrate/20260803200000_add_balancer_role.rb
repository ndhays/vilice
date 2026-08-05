# The Balancer — a **role over Machine**, not a fourth primitive
# (decisions/one-primitive-composed.md). A balancer is a box like any other: same scoped
# key, same record, same ownership and sharing rules. What makes it a balancer is that
# installs point at it and it is told a routing table (`steward route`).
#
# Two columns, no new table. A separate Balancer model would duplicate address, key,
# scope, ownership and sharing — and then have to be kept in step with the Machine it
# actually is.
class AddBalancerRole < ActiveRecord::Migration[8.1]
  def change
    # This box is willing to front others. Not exclusive: a balancer may still run apps.
    add_column :machines, :balancer, :boolean, null: false, default: false

    # Which balancer fronts this install. Null is the ordinary case — an install on the
    # edge is reached at its own box and needs none.
    add_reference :installs, :balancer, null: true, foreign_key: { to_table: :machines }
  end
end
