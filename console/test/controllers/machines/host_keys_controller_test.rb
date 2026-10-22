require "test_helper"

# Trusting a box's new host key: both fingerprints on screen, and the act recorded with
# both (decisions/host-keys-are-pinned-on-the-machine.md). ssh-keyscan is stubbed.
class Machines::HostKeysControllerTest < ActionDispatch::IntegrationTest
  OLD = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk6cg+M3rJ8Zx0wUu4Tx6XDGuKDrH8bc8i1MsTgYaqs".freeze
  NEW = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGs3e3R2tf0dH5MfX1JmfLx1a7dUYGQn9Dx0e6S4qA3x".freeze

  setup do
    @user = users(:one)
    @machine = Machine.create!(name: "edge-1", ssh_host: "10.0.0.1", ssh_private_key: "k",
                               ssh_host_key: OLD, ssh_host_key_trusted_at: 1.day.ago)
    sign_in_as @user
  end

  test "the same key: says so, and offers nothing to press" do
    stub_returning(HostKey, :scan, OLD) { get machine_host_key_path(@machine) }
    assert_response :success
    assert_select "body", /They match/
    assert_select "form[action=?]", machine_host_key_path(@machine), count: 0
  end

  test "a different key: both fingerprints, a warning, and the act" do
    stub_returning(HostKey, :scan, NEW) { get machine_host_key_path(@machine) }
    assert_response :success
    assert_select "code", SshKeypair.fingerprint(OLD)
    assert_select "code", SshKeypair.fingerprint(NEW)
    assert_select ".flash.alert", /do not trust it/
    assert_select "input[name=fingerprint][value=?]", SshKeypair.fingerprint(NEW)
  end

  test "trusting replaces the key and records both fingerprints" do
    stub_returning(HostKey, :scan, NEW) do
      assert_difference -> { Event.where(action: "trusted host key").count }, 1 do
        patch machine_host_key_path(@machine), params: { fingerprint: SshKeypair.fingerprint(NEW) }
      end
    end
    assert_redirected_to settings_machine_path(@machine, anchor: "host-key")
    assert_equal NEW, @machine.reload.ssh_host_key
    event = Event.last
    assert_equal @user.email_address, event.actor
    assert_includes event.summary, SshKeypair.fingerprint(NEW)
    assert_includes event.summary, "replacing #{SshKeypair.fingerprint(OLD)}"
  end

  # The person saw one key; if the box now answers with another, that one was never seen.
  test "a key that changed again since the page was shown is refused" do
    stub_returning(HostKey, :scan, NEW) do
      assert_no_difference -> { Event.count } do
        patch machine_host_key_path(@machine), params: { fingerprint: "SHA256:what-you-saw" }
      end
    end
    assert_equal OLD, @machine.reload.ssh_host_key
    assert_match(/different key from the one you were shown/, flash[:alert])
  end

  test "Settings shows the trusted fingerprint and links to the comparison" do
    get settings_machine_path(@machine)
    assert_select "#host-key code", SshKeypair.fingerprint(OLD)
    assert_select "#host-key a[href=?]", machine_host_key_path(@machine)
  end
end
