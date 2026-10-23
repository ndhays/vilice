# An app read the names it takes values for — env vars, which are secret, secret files —
# live from its library entry, so editing the entry changed what the app sent, and
# deleting it dropped every secret. They are now copied onto the app at create
# (App#inputs). This copies them for the apps made before, from the entry each still
# links to. An app whose entry is already gone has nothing to copy from, and is left as
# it is: it declares nothing, as it already did.
class CopyInputsOntoApps < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "app_templates"
  end

  class App < ActiveRecord::Base
    self.table_name = "apps"
  end

  def up
    App.where.not(app_template_id: nil).find_each do |app|
      config = app.config || {}
      next if config.key?("inputs")

      template = Template.find_by(id: app.app_template_id) or next
      inputs = { "env" => Array(template.env).presence,
                 "secret_files" => Array(template.secret_files).presence }.compact
      next if inputs.empty?

      app.update_columns(config: config.merge("inputs" => inputs))
    end
  end

  # The copies are harmless left in place: the code before this read the entry instead.
  def down; end
end
