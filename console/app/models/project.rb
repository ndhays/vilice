class Project < ApplicationRecord
  include Boxcar::Identifiable
  include Searchable

  # Article I — Identity. A Project IS the client entity Steward Console acts for.
  identifies :entity

  has_many :project_machines, dependent: :destroy
  has_many :machines, through: :project_machines
  # Boxes this project owns. No dependent: deleting an owner is blocked until its
  # boxes are transferred (ProjectsController#destroy) — never a silent nullify.
  has_many :owned_machines, class_name: "Machine", foreign_key: :owner_id, inverse_of: :owner
  # Sharing grants this project holds on *other* owners' boxes. These vanish with
  # the project (the grant is just a permission; the owner's box is untouched).
  has_many :machine_grants, dependent: :destroy
  has_many :apps, dependent: :destroy
  has_many :events, dependent: :nullify
  has_many :labels, as: :labelable, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  scope :starred, -> { where(starred: true) }
end
