# Fleet-wide policy, a single row. `Setting.current` is the one instance.
#
# `apps_library_only` gates the app flow: when on (the default), apps
# must come from the App Library; when off, a custom image is allowed too
# (decisions/open/app-library.md). A Vilice Console-side guardrail, not a security
# boundary — the un-bypassable image allowlist would live on the box.
class Setting < ApplicationRecord
  def self.current
    first_or_create!
  end
end
