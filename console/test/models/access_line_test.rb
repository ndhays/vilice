require "test_helper"

# One line of a box's rights ledger. Nothing here is stored — it is assembled from a
# live `steward actors` read and thrown away — so these pin the reading of that reply.
class AccessLineTest < ActiveSupport::TestCase
  setup { @machine = Machine.create!(name: "edge-1", ssh_host: "x") }

  def line(**actor) = AccessLine.from(@machine, actor.stringify_keys)

  test "an ungated line sits above grant, not beside it" do
    ranked = %w[observe operate grant].map { |s| line(client: "c", scope: s, pinned: true) }
    ungated = line(pinned: false)

    order = (ranked + [ ungated ]).sort_by(&:reach_order).map(&:reach)
    assert_equal %w[ungated grant operate observe], order
    assert ungated.ungated?
    assert_not ranked.last.ungated?
  end

  # Steward parses a comment out only for lines it recognises as grants, so for a
  # hand-added key the holder's handle survives nowhere but `raw`. It is the only
  # thing distinguishing one ungated key from another.
  test "an ungated key takes its handle from the raw line's comment" do
    l = line(pinned: false, key_type: "ssh-ed25519",
             raw: "ssh-ed25519 AAAAC3NzaC1 ops@old-laptop")
    assert_equal "ops@old-laptop", l.name
  end

  test "a raw line with no comment is named as unknown rather than guessed at" do
    l = line(pinned: false, key_type: "ssh-ed25519", raw: "ssh-ed25519 AAAAC3NzaC1")
    assert_equal "unnamed key", l.name
  end

  # A line carrying options does not have its comment in a fixed position. Guessing
  # would invent an owner for the most dangerous row on the page.
  test "a line that does not start with its key type yields no handle" do
    l = line(pinned: false, key_type: "ssh-rsa",
             raw: 'command="/bin/sh",restrict ssh-rsa AAAA someone@host')
    assert_equal "unnamed key", l.name
  end

  test "a Steward grant is named by its client, not its comment" do
    l = line(client: "console", scope: "operate", pinned: true, comment: "console@laptop")
    assert_equal "console", l.name
  end

  test "search matches actor, box, fingerprint and key type" do
    l = line(client: "ci-deployer", scope: "observe", pinned: true,
             key_type: "ssh-ed25519", fingerprint: "SHA256:abc123")
    assert l.matches?("ci-dep")
    assert l.matches?("edge-1")          # the box it opens
    assert l.matches?("SHA256:abc")
    assert l.matches?("ED25519")         # case-insensitive
    assert l.matches?("")                # an empty query is not a filter
    assert_not l.matches?("nothing")
  end
end
