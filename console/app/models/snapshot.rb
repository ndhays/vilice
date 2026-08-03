class Snapshot < ApplicationRecord
  # Observe side — a re-derivable lens, never the source of truth. Ingested from
  # Steward's status.jsonl / live reads (data-model Decision 3).
  belongs_to :machine

  validates :captured_at, presence: true

  scope :recent, -> { order(captured_at: :desc) }
end
