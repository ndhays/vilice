require "test_helper"

# The Access destination: the rights ledger, read off the box rather than stored.
# The half that matters is the ungated key — a line in authorized_keys that Steward
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

  ADMIT = GRANT.merge("client" => "root-key", "scope" => "grant",
                      "fingerprint" => "SHA256:ggg777").freeze

  WATCHER = GRANT.merge("client" => "ci-deployer", "scope" => "observe",
                        "fingerprint" => "SHA256:ooo111").freeze

  UNPINNED = {
    "client" => "", "scope" => "", "key_type" => "ssh-ed25519",
    "fingerprint" => "SHA256:zzz999", "pinned" => false,
    "raw" => "ssh-ed25519 AAAA sneaky@elsewhere"
  }.freeze

  def headings = css_select(".group-head .group-name").map(&:text)
  def actors   = css_select(".access-rows .row-name").map(&:text)

  test "access is behind the login" do
    get access_path
    assert_redirected_to new_session_path
  end

  test "lists each key with actor, box, scope and fingerprint" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ GRANT ])) do
      get access_path
      assert_response :success
      assert_select "h1", /Access/
      assert_select ".access-rows .row-name", "console"
      assert_select ".access-rows .cell-print", /SHA256:abc123/
      # Reach is the heading under the default grouping, so it is not repeated per row.
      assert_select ".group-head .group-name", /Operate/
      assert_select ".access-rows .cell-box a[href=?]", machine_path(@machine)
    end
  end

  # The ladder is the point of the default view: an ungated key has no ceiling at all,
  # which puts it *above* grant rather than beside it. Most reach first.
  test "the default grouping orders every key by how far it reaches" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ WATCHER, GRANT, UNPINNED, ADMIT ])) do
      get access_path
      assert_response :success
      assert_equal [ "Not written by Steward — no ceiling at all",
                     "Grant — can admit other keys",
                     "Operate — can act on the box",
                     "Observe — read-only" ], headings
      assert_equal [ "sneaky@elsewhere", "root-key", "console", "ci-deployer" ], actors
    end
  end

  test "a key steward did not write is called out, not listed quietly" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ UNPINNED, GRANT ])) do
      get access_path
      assert_response :success
      assert_select ".access-rows .row.ungated"
      assert_select "h2", /not written by Steward/
      # It must say what it means, not just flag it.
      assert_match(/without\s+passing the gate/, response.body)
      assert_select ".headline .bad", /1 not written by Steward/
    end
  end

  # The question the old card-per-box layout could not answer at all.
  test "grouping by actor shows where one actor reaches" do
    sign_in_as @user
    other = Machine.create!(name: "node-9", ssh_host: "10.0.0.2")
    stub_returning(Steward::Observe, :actors, ledger([ GRANT ])) do
      get access_path(group: "actor")
      assert_response :success
      # One actor, holding the same key on both boxes.
      assert_equal [ "console" ], headings
      assert_select ".access-rows .row", 2
      assert_select ".access-rows .cell-box a[href=?]", machine_path(other)
      # The actor is the heading here, so the reach badge carries the scope instead.
      assert_select ".access-rows .cell-reach .badge", /operate/
    end
  end

  test "grouping by box is the old per-machine view, as one axis of several" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ GRANT, UNPINNED ])) do
      get access_path(group: "box")
      assert_equal [ "edge-1" ], headings
      # Ungated leads within the box too, for the same reason it leads the page.
      assert_equal [ "sneaky@elsewhere", "console" ], actors
    end
  end

  test "search narrows by actor, box or fingerprint" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([ GRANT, WATCHER ])) do
      get access_path(q: "ci-deployer")
      assert_equal [ "ci-deployer" ], actors

      get access_path(q: "SHA256:abc123")
      assert_equal [ "console" ], actors

      get access_path(q: "no-such-thing")
      assert_select ".empty", /No keys match/
      # The headline counts the fleet, not the query — a search must not look like a fix.
      assert_select ".headline", /2 keys/
    end
  end

  test "an unreachable box reads as unknown, not as nobody" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, { ok: false, error: "connection refused" }) do
      get access_path
      assert_response :success
      assert_select ".panel.readonly", /could not be read/
      assert_select ".unreadable-boxes a[href=?]", machine_path(@machine)
      assert_match(/connection refused/, response.body)
      assert_match(/unknown/, response.body)
      # The dangerous misreading is "no keys shown" == "nobody has access".
      assert_no_match(/nobody can reach/, response.body)
      # And it must not be counted as a box we successfully read.
      assert_select ".headline", /0 keys on 0 boxes/
    end
  end

  # Every box is still named — unknown is not absent — but the reason is said once per
  # reason rather than once per box: the failing case is usually the whole fleet failing
  # the same way, and one line each turns that into a screenful.
  test "unreadable boxes are grouped by reason, and all of them are named" do
    sign_in_as @user
    other = Machine.create!(name: "edge-2", ssh_host: "10.0.0.2")
    odd   = Machine.create!(name: "edge-3", ssh_host: "10.0.0.3")
    replies = { @machine => { ok: false, error: "no ssh key on file" },
                other    => { ok: false, error: "no ssh key on file" },
                odd      => { ok: false, error: "connection refused" } }
    original = Steward::Observe.method(:actors)
    Steward::Observe.define_singleton_method(:actors) { |m, **| replies[m] }
    begin
      get access_path
      assert_response :success
      assert_select ".unreadable-group", 2                  # two reasons, not three boxes
      assert_select ".unreadable-why", /no ssh key on file/
      assert_select ".unreadable-why", /connection refused/
      [ @machine, other, odd ].each do |m|
        assert_select ".unreadable-boxes a[href=?]", machine_path(m), text: m.name
      end
    ensure
      Steward::Observe.define_singleton_method(:actors, original)
    end
  end

  test "a box with an empty ledger says so plainly" do
    sign_in_as @user
    stub_returning(Steward::Observe, :actors, ledger([])) do
      get access_path
      assert_response :success
      assert_match(/nobody can reach these boxes through Steward/, response.body)
    end
  end

  # Re-reading opens an SSH connection to every box in the fleet, so it must not be
  # something a hover, a prefetch or a repeated GET can trigger.
  test "re-read is a POST, and is not reachable by GET" do
    sign_in_as @user
    get "/access/refresh"
    assert_response :not_found

    stub_returning(Steward::Observe, :actors, ledger([ GRANT ])) do
      post refresh_access_path(group: "box")
      assert_redirected_to access_path(group: "box")
    end
  end
end
