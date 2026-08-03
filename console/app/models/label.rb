# A universal key/value label, shared by Projects and Machines (anything
# labelable). Hetzner-style: a key is required, a value is optional — a bare key
# (`shared`, `eu`) is a valid label, as is `env=prod`. Labels are metadata you
# can search and group by; they render as neutral badges, distinct from the
# status/scope badges that carry meaning.
class Label < ApplicationRecord
  belongs_to :labelable, polymorphic: true

  KEY_FORMAT = /\A[a-z0-9][a-z0-9_.\-\/]*\z/i

  validates :key, presence: true, length: { maximum: 63 },
                  format: { with: KEY_FORMAT, message: "may use letters, digits, . _ - /" },
                  uniqueness: { scope: [ :labelable_type, :labelable_id ],
                                message: "is already set on this item" }
  validates :value, length: { maximum: 255 }

  normalizes :key, with: ->(k) { k.to_s.strip }
  normalizes :value, with: ->(v) { v.to_s.strip.presence }

  scope :with_key, ->(k) { where(key: k) }

  # "env=prod" or just "shared".
  def to_s
    value.present? ? "#{key}=#{value}" : key
  end
end
