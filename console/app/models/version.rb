# A released image of a library App — a `(tag, image)` pair. The library curates
# which releases exist; exactly one per app is `latest` (the install default).
# See decisions/open/app-library.md.
class Version < ApplicationRecord
  belongs_to :app

  validates :tag, presence: true, uniqueness: { scope: :app_id }
  validates :image, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
end
