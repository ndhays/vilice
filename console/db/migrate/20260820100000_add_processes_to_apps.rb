# The app's other containers — a worker, a clock. Same image, same env, same secrets,
# same volumes; only the command differs, which is what keeps a worker from ever running
# different code from the web process (steward/internal/app/process.go).
#
# Shape matches the box's spec exactly: { "name", "command" => [] }.
class AddProcessesToApps < ActiveRecord::Migration[8.1]
  def change
    add_column :apps, :processes, :json, default: [], null: false
  end
end
