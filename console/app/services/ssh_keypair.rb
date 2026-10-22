require "tmpdir"
require "open3"

# Generate an ed25519 SSH keypair for a Machine, server-side. The private half is
# stored encrypted (Machine.encrypts, Decision 2) and never leaves Vilice Console; only
# the public half is shown, to be `vilice authorize`d on the box. No gem — shells
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

  # The SHA256 fingerprint of a key line (`type base64 [comment]`), the form `ssh-keygen
  # -lf`, ssh's own prompts and the box's `vilice actors` print: SHA256 of the key blob,
  # base64 without padding. nil when the line holds no key.
  def fingerprint(line)
    blob = Base64.strict_decode64(line.to_s.split[1].to_s)
    return if blob.empty?

    "SHA256:#{Base64.strict_encode64(Digest::SHA256.digest(blob)).delete('=')}"
  rescue ArgumentError
    nil
  end
end
