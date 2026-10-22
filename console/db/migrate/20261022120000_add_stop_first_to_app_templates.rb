# An app that locks its data cannot start beside itself, so its old copy is stopped
# before the new one starts (decisions/stop-first.md). A property of the image, like
# the release command, so it lives on the library entry and is copied to an app at create.
class AddStopFirstToAppTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :app_templates, :stop_first, :boolean, default: false, null: false
  end
end
