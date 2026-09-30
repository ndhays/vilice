# A released image of a library App — a `(tag, image)` pair. The library curates
# which releases exist; exactly one per app is `latest` (the app default).
# See decisions/open/app-library.md.
class Version < ApplicationRecord
  belongs_to :app_template

  validates :tag, presence: true, uniqueness: { scope: :app_template_id }
  validates :image, presence: true
  validate :image_is_digest_pinned


  scope :newest_first, -> { order(created_at: :desc) }

  private

  # The box refuses an unpinned image (`steward/internal/app/deploy.go`: "image must
  # be digest-pinned"), so a floating tag in the library is a release that looks
  # installable and is then rejected at the far end, after someone has built a
  # placement on it. Refuse it here, where it is typed.
  #
  # A tag means something different tomorrow, which is what makes "the image that was
  # running" unanswerable and rollback meaningless — the reason the box holds the line
  # in the first place. The checks mirror `validDigestPin` exactly, including the
  # doubled-prefix case: pasting a value that already carries `sha256:` yields
  # `…@sha256:sha256:…`, which passes a naive contains-check and then fails at the
  # container runtime with "invalid reference format", telling nobody anything.
  DIGEST_MARKER = "@sha256:".freeze

  def image_is_digest_pinned
    return if image.blank?

    i = image.index(DIGEST_MARKER)
    return errors.add(:image, "must be digest-pinned — ref@sha256:… (a tag means " \
                              "something different tomorrow)") if i.nil?

    hex = image[(i + DIGEST_MARKER.length)..].to_s
    if hex.start_with?("sha256:")
      fixed = image.sub("@sha256:sha256:", "@sha256:")
      errors.add(:image, "digest is doubled — the value already carried its own prefix; use #{fixed}")
    elsif hex.length != 64
      errors.add(:image, "digest must be 64 hex characters, got #{hex.length}")
    elsif !hex.match?(/\A[0-9a-f]+\z/)
      errors.add(:image, "digest has a non-hex character")
    end
  end
end
