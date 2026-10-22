# The box's host key, pinned on the Machine rather than in the console's known_hosts —
# a file outside the database, which a container loses on every redeploy, and which
# nothing recorded the trusting of (decisions/host-keys-are-pinned-on-the-machine.md).
class AddSshHostKeyToMachines < ActiveRecord::Migration[8.1]
  def change
    add_column :machines, :ssh_host_key, :text
    add_column :machines, :ssh_host_key_trusted_at, :datetime
  end
end
