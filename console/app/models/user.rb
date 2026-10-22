class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Appearance — this operator's own, not fleet policy. Validated against the
  # registry so a retired theme name can never reach the layout as an attribute
  # no stylesheet answers to.
  validates :theme, inclusion: { in: ->(_) { Theme.names } }
  validates :mode,  inclusion: { in: Theme::MODES }

  # The first user of a deployed console. A box has no shell to run a command in, so the
  # deploy supplies it — CONSOLE_ADMIN_EMAIL, and CONSOLE_ADMIN_PASSWORD as a secret, off
  # the record — and every boot calls this (bin/docker-entrypoint). Only ever the first:
  # once anyone exists it does nothing, so a value left in the spec cannot reset a
  # password or add an account.
  def self.create_first(email, password)
    return if exists? || email.blank? || password.blank?

    create!(email_address: email, password: password)
  end
end
