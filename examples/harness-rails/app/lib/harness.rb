# The harness app's whole behavior, driven entirely by env vars so one published image
# can exercise each axis of the Steward deploy contract — health timing, secrets (env and
# file), a volume-backed counter, a crash, and a memory balloon. See the README for the
# knob → axis mapping. Kept deliberately plain: no database, no framework magic.

require "socket"
require "fileutils"
require "tmpdir"

module Harness
  module_function

  # Monotonic boot mark, so uptime/health timing is immune to wall-clock changes.
  BOOT = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # info is the hello-world payload: who am I, how long up, what config did I get. Proves
  # routing, the injected PORT, plain env delivery, and replica identity (hostname/pid).
  def info
    {
      app: ENV.fetch("APP_NAME", "harness-rails"),
      version: ENV.fetch("APP_VERSION", "dev"),
      stack: "rails #{Rails.version}",
      hostname: Socket.gethostname,
      pid: Process.pid,
      uptime_s: uptime.round(1),
      ready: ready?,
      env: echoed_env,
    }
  end

  def uptime
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - BOOT
  end

  # ready? drives the health endpoint. HEALTH_FAIL keeps it down forever (proves a deploy
  # rolls back safely and never flips traffic); HEALTH_DELAY keeps it down for N seconds
  # after boot (proves the health gate waits for a slow starter).
  def ready?
    return false if truthy?(ENV["HEALTH_FAIL"])
    uptime >= seconds(ENV["HEALTH_DELAY"])
  end

  # secrets_status reports only whether each secret arrived — never the value. SECRET_TOKEN
  # is an env secret; SECRET_FILE points at a mounted file secret.
  def secrets_status
    {
      env_secret_loaded: present?(ENV["SECRET_TOKEN"]),
      file_secret_loaded: file_secret_present?,
      file_secret_path: ENV["SECRET_FILE"],
    }
  end

  def file_secret_present?
    path = ENV["SECRET_FILE"]
    return false if path.nil? || path.empty?
    File.exist?(path) && !File.read(path).strip.empty?
  rescue StandardError
    false
  end

  # bump_counter increments a count persisted under DATA_DIR. Across a blue/green flip the
  # number survives iff the volume does — the way to see persistence (vs ephemeral) work.
  def bump_counter
    dir = data_dir
    FileUtils.mkdir_p(dir)
    file = File.join(dir, "counter")
    n = (File.exist?(file) ? File.read(file).to_i : 0) + 1
    File.write(file, n.to_s)
    { counter: n, data_dir: dir }
  end

  def data_dir
    d = ENV["DATA_DIR"]
    (d.nil? || d.empty?) ? Dir.tmpdir : d
  end

  # start_background! runs the boot-time, non-HTTP behaviors. Called from config.ru, so it
  # only fires for the server (not rake/console). BALLOON_MB holds resident memory to
  # exercise MemoryMax/OOM; CRASH_AFTER exits non-zero to exercise Restart=on-failure.
  def start_background!
    if (mb = ENV.fetch("BALLOON_MB", "0").to_i) > 0
      @balloon = "x" * (mb * 1024 * 1024) # retained reference → stays resident
      warn "harness: holding #{mb}MB (BALLOON_MB)"
    end
    if (s = seconds(ENV["CRASH_AFTER"])) > 0
      Thread.new do
        sleep s
        warn "harness: CRASH_AFTER=#{s}s reached — exiting 1"
        exit!(1)
      end
    end
  end

  # --- small helpers ---

  # Echo only DEMO_*-prefixed vars, so a deploy's `env` is visible without ever leaking a
  # secret or the platform's own injected vars.
  def echoed_env
    ENV.select { |k, _| k.start_with?("DEMO_") }.to_h
  end

  def present?(v)
    !(v.nil? || v.empty?)
  end

  def truthy?(v)
    %w[1 true yes on].include?(v.to_s.strip.downcase)
  end

  # seconds parses "20", "20s", or "500ms" into a Float; anything else is 0.
  def seconds(v)
    return 0.0 if v.nil? || v.empty?
    if (m = v.strip.match(/\A(\d+(?:\.\d+)?)(s|ms)?\z/))
      m[2] == "ms" ? m[1].to_f / 1000 : m[1].to_f
    else
      0.0
    end
  end
end
