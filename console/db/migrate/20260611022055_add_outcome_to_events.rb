class AddOutcomeToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :outcome, :string
    add_column :events, :finished_at, :datetime
    add_column :events, :detail, :text
  end
end
