require "test_helper"

# The Access destination: the rights ledger, read off the box rather than stored.
# The half that matters is the unpinned key — a line in authorized_keys that Steward
# did not write, whose holder reaches the box without passing the gate.
class AccessControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    # There are no machine fixtures; the ledger is per-box, so the page needs one.
    @machine = Machine.create!(name: "edge-1", ssh_host: "10.0.0.1", scope: "observe")
  end

  def ledger(actors, path: "/home/steward/.ssh/authorized_keys")
    { ok: true, at: Time.current,
      data: { "data" => { "path" => path, "actors" => actors } } }
  end

  GRANT = {
    "client" => "console", "scope" => "operate", "key_type" => "ssh-ed25519",
    "fingerprint" => "SHA256:abc123", "comment" => "console@laptop",
    "command" => "/usr/local/bin/steward _exec --client console --scope operate",
    "pinned" => true
  }.freeze

  UNPINNED = {
    "client" => "", "scope" => "", "key_type" => "ssh-ed25519",
    "fingerprint" => "SHA256:zzz999", "pinned" => false,
    "raw" => "ssh-ed25519 AAAA sneaky@elsewhere"
  }.freeze

  test "access is behind the login" do
    get access_path
    assert_redirected_to new_session_path
  end

  test "lists each box's grants with actor, scope and fingerprint" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ GRANT ])) do
      get access_path
      assert_response :success
      assert_select "h1", /Access/
      assert_select "td", "console"
      assert_select "td", /operate/
      assert_select "code", "SHA256:abc123"
    end
  end

  test "a key steward did not write is called out, not listed quietly" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ UNPINNED, GRANT ])) do
      get access_path
      assert_response :success
      assert_select "tr.unpinned"
      assert_select "h2", /not written by Steward/
      # It must say what it means, not just flag it.
      assert_match(/without\s+passing the gate/, response.body)
    end
  end

  test "an unreachable box reads as unknown, not as nobody" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, { ok: false, error: "connection refused" }) do
      get access_path
      assert_response :success
      assert_match(/Unreachable/, response.body)
      assert_match(/unknown, not absent/, response.body)
      # The dangerous misreading is "no grants shown" == "nobody has access".
      assert_no_match(/nobody can reach this box/, response.body)
    end
  end

  test "a box with an empty ledger says so plainly" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([])) do
      get access_path
      assert_response :success
      assert_match(/nobody can reach this box through Steward/, response.body)
    end
  end
end
