# Fleet-wide policy, a single row. `Setting.current` is the one instance.
#
# `installs_library_only` gates the install flow: when on (the default), installs
# must come from the App Library; when off, a custom image is allowed too
# (decisions/open/app-library.md). A Steward Console-side guardrail, not a security
# boundary — the un-bypassable image allowlist would live on the box.
class Setting < ApplicationRecord
  def self.current
    first_or_create!
  end
end
