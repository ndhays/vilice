require "open3"

# The box's host key: the one that proves the console reached the box it meant to.
#
# It is pinned on the Machine (`ssh_host_key`), and every ssh call is given a known_hosts
# file holding that one key and nothing else, so what is trusted lives in the database —
# backed up, the same in every container, and recorded when it changes. A box with no
# pinned key is trusted on first contact, and that is recorded too; after that a
# different key is refused, and only a person replaces it, with both fingerprints in
# front of them (Machines::HostKeysController).
# See decisions/host-keys-are-pinned-on-the-machine.md.
module HostKey
  module_function

  # A known_hosts file for one ssh call: the pinned key if there is one, empty if not.
  # Yields the path and whether a key was pinned (which decides StrictHostKeyChecking).
  def with_known_hosts(machine)
    file = Tempfile.new([ "vilice_known_hosts_", "" ])
    file.write("#{host_pattern(machine)} #{machine.ssh_host_key}\n") if machine.ssh_host_key.present?
    file.close
    yield file.path, machine.ssh_host_key.present?
  ensure
    file&.unlink
  end

  # After a call that ssh let through with an empty file, the key it accepted is in that
  # file. Pin it, unless someone pinned one meanwhile, and record that it was trusted.
  def pin_first_contact(machine, known_hosts_path, actor:)
    key = accepted_key(known_hosts_path)
    return unless key

    pinned = Machine.where(id: machine.id, ssh_host_key: nil)
                    .update_all(ssh_host_key: key, ssh_host_key_trusted_at: Time.current)
    return if pinned.zero?

    machine.reload
    Event.record!(actor: actor, action: "trusted host key", machine: machine,
                  summary: "#{machine.name}: #{SshKeypair.fingerprint(key)}, on first contact")
  end

  # The `type base64` ssh wrote to a known_hosts file, or nil if it wrote nothing.
  def accepted_key(path)
    line = File.readlines(path).map(&:strip).find { |l| l.present? && !l.start_with?("#") }
    type, blob = line&.split&.drop(1)
    "#{type} #{blob}" if type && blob
  end

  # What the box answers with now, asked fresh: `ssh-keyscan` for the same kind of key as
  # the pinned one (ssh prefers that kind once it is pinned), or ed25519. A read: it
  # writes nothing. nil when the box gives no such key.
  def scan(machine)
    type = key_type(machine.ssh_host_key)
    out, _err, _st = Open3.capture3("ssh-keyscan", "-T", "10", "-t", type,
                                    "-p", machine.ssh_port.to_s, "--", machine.ssh_host)
    line = out.lines.map(&:strip).find { |l| l.present? && !l.start_with?("#") }
    _host, key_type, blob = line&.split
    "#{key_type} #{blob}" if key_type && blob
  end

  # ssh-keyscan's -t takes the short names.
  def key_type(key)
    case key.to_s.split.first
    when "ssh-rsa" then "rsa"
    when /\Aecdsa-/ then "ecdsa"
    else "ed25519"
    end
  end

  # How ssh names a host in known_hosts: bare on port 22, `[host]:port` otherwise.
  def host_pattern(machine)
    machine.ssh_port.to_i == 22 ? machine.ssh_host : "[#{machine.ssh_host}]:#{machine.ssh_port}"
  end
end
