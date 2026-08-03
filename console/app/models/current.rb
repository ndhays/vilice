class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # Boxcar's concerns fall back to Current.actor when no actor is passed
  # explicitly (Article VIII). The responsible party for anything Steward Console
  # does is the signed-in user.
  def actor = user
end
