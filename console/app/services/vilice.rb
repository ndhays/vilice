require "open3"
require "json"
require "tempfile"

# Vilice Console's client to a machine's `vilice` CLI over scoped SSH.
#
# The spine of the whole app — observe vs mutate — lives here as two modules kept
# apart on purpose. They share only the transport at the bottom of the file.
#
#   Vilice::Observe — read the record Vilice ships. Zero-privilege by
#     construction: it only ever runs read commands, caches them, and changes
#     nothing. Most of Vilice Console is this.
#
#   Vilice::Mutate  — issue a named, scoped, recorded command (operate). The
#     accountable side: every mutation writes an Event *before* it runs, so the
#     act is witnessed even if it fails (Invariant 2).
#
# A Machine carries its own encrypted SSH key (Decision 2); the transport
# materializes it to a 0600 tempfile only for the length of one call.
module Vilice
  # ── Observe ──────────────────────────────────────────────────────────────
  # Read-only. Cached in solid_cache (Decision 3). A cache miss just re-reads
  # Vilice — the on-box record (plus its off-host backup) is the source of truth.
  module Observe
    module_function

    CACHE_TTL = 30.seconds
    # How much of the tail to ask for. Enough to see a boot and a crash without pulling
    # a whole log across an SSH connection; the view offers the other two.
    DEFAULT_TAIL = 200
    TAILS        = [ 50, 200, 1000 ].freeze

    # Live machine status, cached per machine. Pass refresh: true to bypass.
    # A read also reconciles Vilice Console's stored *projection* of the box —
    # reachability + the running image — so the Status page and the drift rollup
    # have something true to read (decisions/observe-reconciliation.md). It stays a
    # read: it mirrors the box into our own columns, it never authors the box's
    # record. Reconcile lives in the cache-fill block, so it fires only when we
    # actually talked to the box, not on a cache hit.
    def status(machine, refresh: false)
      cached(machine, "status", refresh: refresh) do
        Vilice.read(machine, "status --json").tap { |result| reconcile(machine, result) }
      end
    end

    # Project a status read onto the machine's stored columns. A projection, not a
    # witnessed act: update_columns, so no callbacks, no updated_at churn, no Event.
    def reconcile(machine, result)
      unless result[:ok]
        # last_seen_at is "when we last heard from it" — a failed read must not move it.
        machine.update_columns(status: "unreachable")
        return
      end

      machine.update_columns(status: "reachable", last_seen_at: result[:at] || Time.current)
      reconcile_name(machine, result.dig(:data, "data", "machine", "hostname"))
      reconcile_role(machine, result.dig(:data, "data", "role"))
      reconcile_running_images(machine, result.dig(:data, "data", "apps"))
    end

    # What the box was prepared as, mirrored onto the column the fleet list reads.
    #
    # The role is **the box's fact, and it is set once**: `vilice prepare <role>`
    # writes it, and re-preparing into the other role is refused — you take the apps
    # off, uninstall, and prepare again (blueprint/vilice/provision.md). So the
    # console does not get an opinion about it. It used to: a button offered "Make
    # this a balancer", which wrote this column with nothing behind it, and a `host`
    # so marked would accept balanced apps and then be refused by its own box.
    #
    # A box we have not read reports no role, and that is *unknown*, not "host" — so
    # a blank leaves the column alone rather than quietly demoting it.
    def reconcile_role(machine, role)
      return if role.blank?
      is_balancer = role.to_s == "balancer"
      machine.update_columns(balancer: is_balancer) unless machine.balancer? == is_balancer
    end

    # The name mirrors the box: at Add time we seed it with the SSH host (we can't read
    # the box yet), and the first read renames it to the box's reported hostname
    # (decisions/machine-name-mirrors-the-box.md). Only the still-provisional name is
    # replaced — a name already mirrored (or set in seeds) is left alone — and never to
    # one another box holds (name is unique; update_columns skips that validation).
    def reconcile_name(machine, hostname)
      return if hostname.blank? || machine.name == hostname
      return unless machine.name == machine.ssh_host
      return if Machine.where.not(id: machine.id).exists?(name: hostname)
      machine.update_columns(name: hostname)
    end

    # Set each live target's current_image from what the box reports it's running —
    # the input drift detection needs (placement.in_sync?). Retired targets and
    # apps we don't track are ignored; an app we expect but the box doesn't report is
    # left untouched (failed-state detection needs a box health field we don't get yet).
    def reconcile_running_images(machine, apps)
      return if apps.blank?

      running = apps.index_by { |a| a["name"] }
      machine.placements.includes(:app).each do |placement|
        next if placement.retired?
        box_app = running[placement.app.name]
        placement.update_columns(current_image: box_app["image"]) if box_app && box_app["image"].present?
      end
    end

    # The box's rights ledger — who may act on it, at what scope, and any key in
    # authorized_keys that Vilice did not write. A read: it holds no privilege and
    # writes nothing to the chain. See blueprint/vilice/auth.md.
    def actors(machine, refresh: false)
      cached(machine, "actors", refresh: refresh) do
        Vilice.read(machine, "actors --json")
      end
    end

    # Every box's ledger at once, for the fleet-wide Access page. Asked in parallel, a
    # few at a time, so the page costs about the slowest box rather than the sum of them
    # — one unreachable box is one timeout, not one added to everyone else's wait.
    #
    # The width stays under the database pool (config/database.yml, 5): each worker
    # touches the cache, and the request thread holds a connection of its own. Each
    # worker runs inside the app executor, which gives it its own connections and hands
    # them back; the request thread lets go of the autoload lock while it waits, or a
    # worker that needs to load a constant would wait on it forever.
    READ_WIDTH = 4
    def actors_of(machines, refresh: false)
      machines = machines.to_a
      queue    = Queue.new.tap { |q| machines.each { |m| q << m } }
      results  = {}
      lock     = Mutex.new
      workers  = Array.new([ READ_WIDTH, machines.size ].min) do
        Thread.new do
          Rails.application.executor.wrap do
            while (machine = (queue.pop(true) rescue nil))
              result = actors(machine, refresh: refresh)
              lock.synchronize { results[machine] = result }
            end
          end
        end
      end
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { workers.each(&:join) }
      machines.to_h { |m| [ m, results[m] ] }
    end

    # Recent doctor check, cached. Same read contract as status.
    def doctor(machine, refresh: false)
      cached(machine, "doctor", refresh: refresh) do
        Vilice.read(machine, "doctor --json")
      end
    end

    # The box's own record — entries + a chain-integrity check. The witnessed
    # half of the chain (decisions/two-records.md); a read, changes nothing.
    def record(machine, refresh: false)
      cached(machine, "record", refresh: refresh) do
        Vilice.read(machine, "record --json")
      end
    end

    # An app's log tail, straight off the box. `vilice logs` is a passthrough to
    # `podman logs` — the container is the source of truth and Vilice stores nothing —
    # so this is the one read that owns no projection: it mirrors nothing into our
    # columns and answers only the question that was just asked.
    #
    # **Deliberately not cached.** A status is a projection you compare over time; a log
    # tail is a stream someone asked for *now*, usually while watching a deploy. Handing
    # back a 30-second-old tail would be a lie in the shape of a feature.
    #
    # It is `observe` scope, which is the point: you can read the logs of a box whose key
    # cannot act on it — exactly when you most want to.
    def logs(machine, app, tail: DEFAULT_TAIL)
      # The name reaches a command line, so it is checked here rather than trusted from
      # a caller. `App` already enforces this charset; a second guard at the seam
      # costs nothing and is the difference between a bug and a flag injection.
      return { ok: false, reached: true, error: "#{app.inspect} is not a valid app name." } unless
        app.to_s.match?(App::NAME_FORMAT)

      Vilice.read(machine, "logs #{app} --tail #{Integer(tail)} --json")
    end

    def cached(machine, verb, refresh:)
      key = "vilice:observe:#{verb}:#{machine.id}"
      Rails.cache.delete(key) if refresh
      Rails.cache.fetch(key, expires_in: CACHE_TTL) { yield }
    end
  end

  # ── Mutate ───────────────────────────────────────────────────────────────
  # Witnessed, accountable writes. Records an Event before issuing the command,
  # so nothing happens off the record. Vilice holds the authoritative,
  # hash-chained record; this Event is Vilice Console's local mirror of the intent.
  module Mutate
    module_function

    # Issue an operate-scoped command. `actor` is the responsible human (Article
    # VIII); `action` is the past-tense fact for the feed. The Event is written
    # **pending** first — record before act — then the same row is settled
    # ok/failed when the command returns. A crash between the two leaves a pending
    # row: honest evidence that we issued the act but never learned its result.
    # Returns the event and the transport result.
    def run(machine, command, actor:, action:, app: nil, summary: nil, stdin: nil)
      event = Event.record!(
        actor: actor, action: action, machine: machine, app: app,
        summary: summary || machine.name,
        outcome: "pending", raw: { command: command }
      )
      result = Vilice.read(machine, command, stdin: stdin)
      event.settle!(result[:ok] ? "ok" : "failed", detail: result[:ok] ? nil : result[:error],
                    output: result[:ok] ? settled_output(result) : result[:output].presence || result[:error],
                    exit_status: result[:exit_status])
      { event: event, result: result }
    end

    # What the entry keeps of a successful act: the box's reply, and under it whatever
    # its tools printed — for `apply-updates` that is apt's own account of what changed,
    # which is the part worth reading. The reply leads, so a long log is what gets cut.
    def settled_output(result)
      return result[:data] if result[:log].blank?

      "#{JSON.pretty_generate(result[:data])}\n\n#{result[:log].strip}"
    end
  end

  # ── Transport (shared) ─────────────────────────────────────────────────────
  module_function

  # Run a command over scoped SSH and parse its JSON reply. Used by both sides;
  # the scope ceiling is enforced on the box by Vilice, not here. `stdin` carries
  # a payload piped to the remote command — the deploy envelope (secret values ride
  # here, never the recorded command line); nil for everything else.
  def read(machine, command, stdin: nil)
    # Dev/test only: when fake-observe is on, answer from a canned envelope instead
    # of touching the network, so seeded scenarios render with no box (Fake.on?
    # is false in production by construction). See app/services/vilice/fake.rb.
    return Fake.envelope(machine, command) if Fake.on?

    out, err, st = ssh(machine, command, stdin: stdin)
    if st.success?
      # stdout is the reply and nothing else; what the box's tools printed while it
      # worked — apt, podman, caddy — arrives on stderr and is kept as the log.
      { ok: true, reached: true, data: JSON.parse(out), log: err.presence, at: Time.current }
    else
      # **`reached` is not `ok`.** ssh exits 255 when *ssh itself* could not get through —
      # an unauthorized key, a refused connection, a box that is not there. Any other
      # status is the remote command's own, which means we did reach the box and Vilice
      # answered badly. Two different problems with two different fixes, and the raw
      # output names neither, so the caller gets told which one this was.
      reached = st.exitstatus != 255
      changed = !reached && host_key_changed?(err)
      { ok: false, reached: reached, host_key_changed: changed,
        error: changed ? host_key_message(machine) : failure_message(out, err, st),
        output: transcript(out, err), exit_status: st.exitstatus, at: Time.current }
    end
  rescue JSON::ParserError
    # A reply we could not read is still a reply: something answered. The exit status
    # goes with it, because "exit 0, unreadable" and "exit 1, unreadable" are different
    # news — the first is a box that says it succeeded.
    { ok: false, reached: true, exit_status: st&.exitstatus, output: transcript(out, err),
      error: "unparseable reply: #{out.to_s.strip.truncate(200)}", at: Time.current }
  rescue => e
    { ok: false, reached: false, error: e.message, at: Time.current }
  end

  # A refusal from Vilice is a `Result` — `{"code":…,"message":…}` on stdout, and the
  # CLI exits non-zero for any code but `ok`. Handing the operator that JSON was showing
  # them our transport instead of their answer, so the sentence inside it wins when there
  # is one. Otherwise it is whatever was said on stderr — ssh's own complaints land
  # there — then stdout, then the bare exit status.
  def failure_message(out, err, status)
    parsed = JSON.parse(out.to_s) rescue nil
    if parsed.is_a?(Hash) && parsed["message"].present?
      parsed["message"].to_s.strip
    else
      err.to_s.strip.presence || out.to_s.strip.presence || "ssh exited #{status.exitstatus}"
    end
  end

  # Everything that came back, for the record entry: the reply, then the log.
  def transcript(out, err)
    [ out, err ].map { |s| s.to_s.strip }.reject(&:blank?).join("\n\n").presence
  end

  # ssh refuses to connect when a host answers with a different key than the one it
  # remembered. That is the right refusal — it is what a machine-in-the-middle looks
  # like — and also exactly what a rebuilt box looks like.
  def host_key_changed?(err)
    err.to_s.match?(/REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed/)
  end

  # ssh's own text for this is forty lines of capitals. Say what happened, the one
  # command that fixes the innocent case, and that the other case exists.
  def host_key_message(machine)
    host = machine.ssh_port.to_i == 22 ? machine.ssh_host : "[#{machine.ssh_host}]:#{machine.ssh_port}"
    "#{machine.name} answered with a different SSH host key than the one Vilice Console " \
      "remembered, so it refused to connect. If you rebuilt the box, forget the old key — " \
      "run `ssh-keygen -R #{host}` as the user the console runs as — and read it again. " \
      "If you did not, something else is answering at that address."
  end

  def ssh(machine, command, stdin: nil)
    with_key(machine) do |key_path|
      cmd = [
        "ssh", "-i", key_path,
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=10",
        # Never prompt: a read must fail fast, not block the request on an
        # interactive password fallback when the key is wrong or the box is gone.
        "-o", "BatchMode=yes",
        "-o", "PreferredAuthentications=publickey",
        "-o", "PasswordAuthentication=no",
        "-p", machine.ssh_port.to_s,
        "#{machine.ssh_user}@#{machine.ssh_host}", command
      ]
      # stdout and stderr apart: the reply is JSON on stdout, and everything else the
      # box says — its tools' output, ssh's own errors — is on stderr.
      stdin ? Open3.capture3(*cmd, stdin_data: stdin) : Open3.capture3(*cmd)
    end
  end

  # Materialize the machine's encrypted key to a private tempfile for one call.
  def with_key(machine)
    raise "machine #{machine.name} has no ssh key on file" if machine.ssh_private_key.blank?

    file = Tempfile.new([ "vilice_key_", "" ])
    file.write(machine.ssh_private_key)
    file.write("\n") unless machine.ssh_private_key.end_with?("\n")
    file.close
    File.chmod(0o600, file.path)
    yield file.path
  ensure
    file&.unlink
  end
end
