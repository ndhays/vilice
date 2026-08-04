# Exposure — how the app is reached, which is what decides whether a count above 1 can
# mean anything (decisions/one-primitive-composed.md).
#
#   edge     — the box faces the internet and terminates its own TLS; DNS points at the
#              box. One box, one IP, so count is 1. Scaling here would need round-robin
#              DNS, which that decision rejects.
#   balanced — the box is a backend; DNS points at a balancer in front of it. Scaling is
#              then free, because count 1…N is just more upstreams.
#
# Default `edge`: it is the simple single-box case, and it is the one that works without
# anything else existing.
class AddExposureToInstalls < ActiveRecord::Migration[8.1]
  def change
    add_column :installs, :exposure, :string, null: false, default: "edge"

    # Every existing install predates the choice and is served straight off its box, so
    # `edge` is the truthful backfill as well as the default. Any that already asked for
    # more than one box were stating something the edge cannot deliver — surface those as
    # balanced rather than silently clamping an intention someone deliberately set.
    reversible do |dir|
      dir.up { execute "UPDATE installs SET exposure = 'balanced' WHERE count > 1" }
    end
  end
end
