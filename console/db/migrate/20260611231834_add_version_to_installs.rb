class AddVersionToInstalls < ActiveRecord::Migration[8.1]
  def change
    # Which library release this install was deployed from; nil for custom images.
    add_reference :installs, :version, null: true, foreign_key: true
  end
end
