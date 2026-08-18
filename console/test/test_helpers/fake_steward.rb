require "json"

# Tier-1 contract testing for the Steward Console → Steward protocol, offline.
#
# A scripted stand-in for the scoped-SSH transport. It replaces `Steward.ssh` (the
# one subprocess seam at the bottom of app/services/steward.rb), so the real
# `Steward.read` JSON-and-error handling still runs — only the network is gone. It
# records every command Steward Console issues and answers from a script, so a test can
# assert *what Steward Console sent* and *how it handled the reply*, with no ssh and no box.
#
# Install it with `with_fake_steward` (see test_helper.rb).
module FakeSteward
  # Minimal Process::Status stand-in — `read` only asks `success?` / `exitstatus`.
  # The status matters beyond pass/fail: **255 is ssh's own**, meaning it never got
  # through, and `Steward.read` turns that into `reached: false`. So a test can script
  # a box that refused the act (a remote non-zero) apart from one that was never
  # reached at all (255), which are different failures with different fixes.
  class Status
    def initialize(success, exitstatus = nil)
      @success    = success
      @exitstatus = exitstatus || (success ? 0 : 1)
    end

    def success?
      @success
    end

    attr_reader :exitstatus
  end

  # Records issued commands and replies from a script. `ssh` matches the real
  # `Steward.ssh` shape: it returns `[combined_output, status]` (Open3.capture2e).
  class Transport
    attr_reader :calls

    def initialize
      @calls = []
      @replies = []
    end

    # Script a reply, matched by exact string or Regexp. Give `data` (encoded as a
    # successful JSON stdout) for the common case, or raw `stdout` + `success:` to
    # exercise non-zero exits and unparseable output. Returns self, so calls chain.
    # `exit_status:` scripts the exact status — pass 255 for "ssh never got through".
    # Spelled out rather than `exit:`, which would shadow `Kernel#exit` and make every
    # reader stop and check.
    def on(pattern, data: nil, stdout: nil, success: true, exit_status: nil)
      @replies << { pattern: pattern, data: data, stdout: stdout, success: success,
                    exit_status: exit_status }
      self
    end

    # The `Steward.ssh` stand-in: record the call (incl. any stdin payload — the
    # deploy envelope), then reply from the script. An unscripted command gets a
    # benign empty-JSON success, so a test only scripts what it cares about.
    def ssh(machine, command, stdin: nil)
      @calls << { machine: machine, command: command, stdin: stdin }
      reply = @replies.find { |r| matches?(r[:pattern], command) } || { success: true, data: {} }
      out = reply[:stdout] || JSON.generate(reply[:data] || {})
      [ out, Status.new(reply[:success], reply[:exit_status]) ]
    end

    def commands
      @calls.map { |c| c[:command] }
    end

    # Did Steward Console issue a command matching `pattern` (string or Regexp)?
    def issued?(pattern)
      @calls.any? { |c| matches?(pattern, c[:command]) }
    end

    # The stdin payload sent with the first command matching `pattern` (the deploy
    # envelope, as a JSON string), or nil.
    def stdin_for(pattern)
      @calls.find { |c| matches?(pattern, c[:command]) }&.dig(:stdin)
    end

    private

    def matches?(pattern, command)
      pattern.is_a?(Regexp) ? command.match?(pattern) : command == pattern
    end
  end
end
