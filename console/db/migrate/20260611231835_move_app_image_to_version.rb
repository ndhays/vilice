class MoveAppImageToVersion < ActiveRecord::Migration[8.1]
  # Image moves off App onto Version. Seed each existing App that has an image with an
  # initial "v1" version, marked latest. SQLite; pre-production data is small.
  def up
    execute(<<~SQL)
      INSERT INTO versions (app_id, tag, image, latest, created_at, updated_at)
      SELECT id, 'v1', image, 1, created_at, CURRENT_TIMESTAMP
      FROM apps
      WHERE image IS NOT NULL AND image != ''
    SQL
    remove_column :apps, :image
  end

  def down
    add_column :apps, :image, :string
    execute(<<~SQL)
      UPDATE apps SET image = (
        SELECT image FROM versions WHERE versions.app_id = apps.id AND versions.latest = 1 LIMIT 1
      )
    SQL
  end
end
