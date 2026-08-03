require "tmpdir"
require "open3"

# Generate an ed25519 SSH keypair for a Machine, server-side. The private half is
# stored encrypted (Machine.encrypts, Decision 2) and never leaves Steward Console; only
# the public half is shown, to be `steward authorize`d on the box. No gem — shells
# `ssh-keygen` in a throwaway dir.
module SshKeypair
  module_function

  def generate(comment: "console")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "key")
      _out, status = Open3.capture2e(
        "ssh-keygen", "-t", "ed25519", "-N", "", "-C", comment, "-f", path
      )
      raise "ssh-keygen failed" unless status.success?

      { private: File.read(path), public: File.read("#{path}.pub").strip }
    end
  end
end
