require "test_helper"

class SshKeypairTest < ActiveSupport::TestCase
  test "generate returns a private block and an ed25519 public line" do
    keys = SshKeypair.generate(comment: "console@box")
    assert_match(/PRIVATE KEY/, keys[:private])
    assert_match(/\Assh-ed25519 \S+ console@box\z/, keys[:public])
  end
end
