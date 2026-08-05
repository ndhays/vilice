# The routing table a balancer should be serving — **derived, never hand-authored**
# (decisions/one-primitive-composed.md). It is computed from the installs that select this
# balancer and the boxes those installs are actually serving from, so there is no stored
# copy to drift from the placements it describes.
#
# This is the *plan* half. What the box reports fronting (`steward status` → `routes`) is
# the other half, and the gap between them is shown rather than closed — applying the
# table is a witnessed act like any other
# (decisions/drift-is-surfaced-never-closed.md).
class RoutingTable
  # Backends are reached on plain HTTP at the box's own edge. The app's `port` is the
  # port *inside its container*, published only on the backend's loopback, so it is not
  # reachable from here; the backend's own Caddy is, and it routes by hostname. Caddy
  # forwards the Host header by default, so the backend matches the same hostname the
  # balancer was asked for and hands off to the app. TLS terminates at the balancer,
  # which is what lets a backend be private.
  BACKEND_PORT = 80

  Route = Struct.new(:hostnames, :upstreams, :install, keyword_init: true)

  def self.for(machine) = new(machine).routes

  def initialize(machine)
    @machine = machine
  end

  # One route per install this balancer fronts, in a stable order so the rendered table
  # and the record line don't churn between reads.
  def routes
    @machine.fronted_installs.includes(install_targets: :machine).order(:name).filter_map do |install|
      next if install.hostname.blank?

      upstreams = upstreams_for(install)
      next if upstreams.empty?

      Route.new(hostnames: [ install.hostname ], upstreams: upstreams, install: install)
    end
  end

  # The envelope `steward route` reads on stdin. Struct-to-JSON is deliberate and
  # narrow — the box is told hostnames and upstreams and nothing else about our model.
  def self.envelope(machine)
    { routes: self.for(machine).map { |r| { hostnames: r.hostnames, upstreams: r.upstreams } } }
  end

  private

  # Only boxes actually serving the app. A placement we asked for but that isn't up is
  # not an upstream — routing traffic to it would turn a placement gap into a 502, and
  # the gap is supposed to be visible instead.
  def upstreams_for(install)
    install.live_targets
           .select { |t| t.install_running? && !t.machine.seen_unreachable? }
           .map { |t| "#{t.machine.ssh_host}:#{BACKEND_PORT}" }
           .uniq
           .sort
  end
end
