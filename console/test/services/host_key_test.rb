require "test_helper"

# The box's host key, pinned on the Machine (decisions/host-keys-are-pinned-on-the-machine.md).
# What reaches the network — ssh itself, ssh-keyscan — is stubbed; this is the bookkeeping
# around it: what each call is told to trust, and what first contact pins and records.
class HostKeyTest < ActiveSupport::TestCase
  KEY_A = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk6cg+M3rJ8Zx0wUu4Tx6XDGuKDrH8bc8i1MsTgYaqs".freeze
  KEY_B = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGs3e3R2tf0dH5MfX1JmfLx1a7dUYGQn9Dx0e6S4qA3x".freeze

  # A Process::Status stand-in: the ssh seam only reads exitstatus.
  Status = Struct.new(:exitstatus) { def success? = exitstatus.zero? }

  setup do
    @machine = Machine.create!(name: "box-1", ssh_host: "10.0.0.1", ssh_private_key: "k")
  end

  test "a pinned key is the only thing a call trusts, named the way ssh names the host" do
    @machine.update!(ssh_host_key: KEY_A)
    HostKey.with_known_hosts(@machine) do |path, pinned|
      assert pinned
      assert_equal "10.0.0.1 #{KEY_A}\n", File.read(path)
    end
    @machine.update!(ssh_port: 2222)
    HostKey.with_known_hosts(@machine) { |path, _| assert_equal "[10.0.0.1]:2222 #{KEY_A}\n", File.read(path) }
  end

  test "with nothing pinned the file starts empty, and a call is first contact" do
    HostKey.with_known_hosts(@machine) do |path, pinned|
      assert_not pinned
      assert_equal "", File.read(path)
    end
  end

  test "first contact that gets through pins the key and records it, once" do
    ssh_writes(KEY_A, exit: 0) do
      assert_difference -> { Event.where(action: "trusted host key").count }, 1 do
        Vilice.send(:ssh, @machine, "status --json")
      end
    end
    assert_equal KEY_A, @machine.reload.ssh_host_key
    assert @machine.ssh_host_key_trusted_at
    assert_match(/on first contact/, Event.last.summary)
    assert_includes Event.last.summary, @machine.ssh_host_key_fingerprint

    # Pinned now: a later call is not first contact, and records nothing.
    ssh_writes(KEY_B, exit: 0) do
      assert_no_difference -> { Event.count } do
        Vilice.send(:ssh, @machine, "status --json")
      end
    end
    assert_equal KEY_A, @machine.reload.ssh_host_key
  end

  # ssh exits 255 when it could not get through — a refused key, a wrong address. A box
  # that answered but did not accept the key it authorized proves nothing about itself.
  test "first contact that does not get through pins nothing" do
    ssh_writes(KEY_A, exit: 255) do
      assert_no_difference -> { Event.count } do
        Vilice.send(:ssh, @machine, "status --json")
      end
    end
    assert_nil @machine.reload.ssh_host_key
  end

  test "ssh-keyscan is asked for the kind of key that is pinned" do
    assert_equal "ed25519", HostKey.key_type(nil)
    assert_equal "ed25519", HostKey.key_type(KEY_A)
    assert_equal "rsa", HostKey.key_type("ssh-rsa AAAAB3")
    assert_equal "ecdsa", HostKey.key_type("ecdsa-sha2-nistp256 AAAAE2")
  end

  private

  # Stand in for the ssh call: write what ssh would have accepted into the known_hosts
  # file it was given, and exit as told.
  def ssh_writes(key, exit:)
    original = Vilice.method(:ssh_call)
    Vilice.define_singleton_method(:ssh_call) do |machine, _cmd, _key, known_hosts, pinned, _stdin|
      File.write(known_hosts, "#{HostKey.host_pattern(machine)} #{key}\n") unless pinned
      [ "{}", "", Status.new(exit) ]
    end
    yield
  ensure
    Vilice.define_singleton_method(:ssh_call, original)
  end
end
