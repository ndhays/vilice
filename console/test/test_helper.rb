ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/fake_vilice"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Temporarily replace a singleton method with one returning `value`, then
    # restore it. Used to keep the SSH transport offline in tests.
    # Stub every Vilice observe read at once, offline by default.
    #
    # Stubbing verbs one at a time means the day someone adds a fifth read to the
    # machine page, every test that renders it quietly starts making real SSH
    # attempts — which is exactly what happened when a fourth was added: the suite
    # went from 1.7s to 11s and still passed. Stub the surface, not the verb.
    def stub_observe(**reads)
      offline = { ok: false, error: "stubbed offline" }
      verbs = %i[status record actors doctor]
      originals = verbs.to_h { |v| [ v, Vilice::Observe.method(v) ] }
      verbs.each do |verb|
        value = reads.fetch(verb, offline)
        Vilice::Observe.define_singleton_method(verb) { |*, **| value }
      end
      yield
    ensure
      originals&.each { |verb, m| Vilice::Observe.define_singleton_method(verb, m) }
    end

    # Capture what a mutate would have sent, without sending it. Yields, then
    # returns the captured call — so a test can assert on the command *and* on what
    # rode stdin, which is where the deploy spec lives.
    #
    # `result:` is what the fake transport reports back; `refuse:` makes the call
    # itself a failure, for tests asserting the box is never reached.
    def stub_mutate(result: { ok: true }, refuse: false)
      captured = nil
      original = Vilice::Mutate.method(:run)
      Vilice::Mutate.define_singleton_method(:run) do |machine, command, **kw|
        raise "the box must not be called" if refuse
        captured = { machine: machine, command: command, stdin: kw[:stdin],
                     app: kw[:app], action: kw[:action] }
        { event: nil, result: result }
      end
      yield
      captured
    ensure
      Vilice::Mutate.define_singleton_method(:run, original)
    end

    def stub_returning(owner, name, value)
      original = owner.method(name)
      owner.define_singleton_method(name) { |*, **| value }
      yield
    ensure
      owner.define_singleton_method(name, original)
    end

    # Install a scripted, offline Vilice transport for the block (Tier-1 contract
    # tests). Replaces the `Vilice.ssh` subprocess seam with a FakeVilice::Transport,
    # so the real read/parse/error path runs but nothing touches the network. Yields
    # the fake: script replies with `.on(...)`, then assert with `.issued?`/`.commands`.
    def with_fake_vilice
      fake = FakeVilice::Transport.new
      original = Vilice.method(:ssh)
      Vilice.define_singleton_method(:ssh) { |machine, command, stdin: nil| fake.ssh(machine, command, stdin: stdin) }
      yield fake
    ensure
      Vilice.define_singleton_method(:ssh, original)
    end
  end
end
