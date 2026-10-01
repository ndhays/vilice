require "test_helper"

class MachineTest < ActiveSupport::TestCase
  def new_machine(**attrs)
    Machine.new({ name: "box-#{SecureRandom.hex(4)}", ssh_host: "10.0.0.1" }.merge(attrs))
  end

  test "ssh_private_key is encrypted at rest but readable in app (Decision 2)" do
    m = new_machine(ssh_private_key: "PRIVATE-KEY-MATERIAL")
    m.save!
    raw = Machine.connection.select_value("SELECT ssh_private_key FROM machines WHERE id = #{m.id}")
    refute_includes raw.to_s, "PRIVATE-KEY-MATERIAL", "key must not be stored in plaintext"
    assert_equal "PRIVATE-KEY-MATERIAL", Machine.find(m.id).ssh_private_key
  end

  test "defaults to observe scope, not-yet-seen status, and dedicated sharing" do
    m = new_machine
    assert m.observe?
    assert m.seen_unknown?
    assert m.sharing_dedicated?
    assert m.unowned?
  end

  test "validates port range and required fields" do
    refute new_machine(ssh_port: 70_000).valid?
    refute new_machine(ssh_host: nil).valid?
    refute new_machine(name: nil).valid?
  end

  test "a dedicated box permits only its owner; sharing widens it (machine-ownership)" do
    a = Project.create!(name: "A-#{SecureRandom.hex(2)}")
    b = Project.create!(name: "B-#{SecureRandom.hex(2)}")
    m = new_machine(owner: a)
    m.save!

    # dedicated → owner only
    assert m.permits?(a)
    refute m.permits?(b)
    refute ProjectMachine.new(project: b, machine: m).valid?, "a dedicated box won't take a non-owner"

    # everyone → anyone
    m.update!(sharing: "everyone")
    assert m.permits?(b)
    assert ProjectMachine.new(project: b, machine: m).valid?

    # list → owner + allow-listed only
    m.update!(sharing: "list")
    refute m.permits?(b)
    MachineGrant.create!(machine: m, project: b)
    assert m.reload.permits?(b)
    assert m.permits?(a), "the owner is always permitted"
  end

  test "an unowned dedicated box permits no one (inert until re-owned or shared)" do
    m = new_machine
    m.save!
    assert m.unowned?
    refute m.permits?(Project.create!(name: "X-#{SecureRandom.hex(2)}"))
  end

  test "authorize_command surfaces the pubkey, client, and scope — nil without a key" do
    assert_nil new_machine(scope: "operate").authorize_command
    m = new_machine(scope: "operate", ssh_public_key: "ssh-ed25519 AAAAKEY console@box")
    cmd = m.authorize_command
    assert cmd.start_with?("sudo -u _vilice vilice authorize "), "granting runs as the service account"
    assert_includes cmd, "ssh-ed25519 AAAAKEY console@box"
    assert_includes cmd, "--client console"
    assert_includes cmd, "--scope operate"
  end

  test "shared scope covers everyone and list, not dedicated" do
    ded = new_machine; ded.save!
    every = new_machine(sharing: "everyone"); every.save!
    listed = new_machine(sharing: "list"); listed.save!
    assert_includes Machine.shared, every
    assert_includes Machine.shared, listed
    refute_includes Machine.shared, ded
  end

  # The edge a box sits behind is read through the apps it runs — the
  # relationship is placement, not machine-to-machine.
  test "behind names the balancers fronting this box's apps, never itself" do
    project = Project.create!(name: "Edge-unit")
    edge    = Machine.create!(name: "edge-1", ssh_host: "x", scope: "operate", balancer: true)
    host    = Machine.create!(name: "host-1", ssh_host: "x")
    plain   = Machine.create!(name: "plain-1", ssh_host: "x")

    fronted = project.apps.create!(name: "app-a", image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                       exposure: "balanced", balancer: edge)
    fronted.placements.create!(machine: host, status: "running")
    # The balancer also runs the app it fronts: it is not behind itself.
    fronted.placements.create!(machine: edge, status: "running")

    assert_equal [ edge ], host.reload.behind
    assert_equal [],       edge.reload.behind
    assert_equal [],       plain.reload.behind
  end
end
