class AddOutputToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :output, :json
    add_column :events, :exit_status, :integer
  end
end
