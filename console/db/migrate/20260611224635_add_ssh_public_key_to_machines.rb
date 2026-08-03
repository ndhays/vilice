class AddSshPublicKeyToMachines < ActiveRecord::Migration[8.1]
  def change
    add_column :machines, :ssh_public_key, :text
  end
end
