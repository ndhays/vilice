# Read every machine so reconciliation runs fleet-wide, keeping the Status page true
# for boxes nobody has opened. Each read is the same scoped, cached observe call a
# page visit makes (refresh: true to bypass the per-machine cache) — and reconciling
# the stored projection is its side effect (decisions/observe-reconciliation.md).
#
# One box being down must not stall the sweep, so a failed read just marks that box
# unreachable (reconcile does this) and we move on. Scheduled in config/recurring.yml;
# the cadence is a flat interval for v1 — large-fleet batching/backoff is open
# (decisions/open/status-signals.md).
class FleetObserveJob < ApplicationJob
  queue_as :default

  def perform
    Machine.find_each do |machine|
      Steward::Observe.status(machine, refresh: true)
    rescue => e
      Rails.logger.warn("FleetObserveJob: #{machine.name} read failed: #{e.message}")
    end
  end
end
