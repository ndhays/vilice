class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Appearance — this operator's own, not fleet policy. Validated against the
  # registry so a retired theme name can never reach the layout as an attribute
  # no stylesheet answers to.
  validates :theme, inclusion: { in: -> (_) { Theme.names } }
  validates :mode,  inclusion: { in: Theme::MODES }
end
