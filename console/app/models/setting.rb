# Fleet-wide policy, a single row. `Setting.current` is the one instance.
#
# `apps_library_only` gates the app flow: when on (the default), apps
# must come from the App Library; when off, a custom image is allowed too
# (decisions/open/app-library.md). A Vilice Console-side guardrail, not a security
# boundary — the un-bypassable image allowlist would live on the box.
class Setting < ApplicationRecord
  # The machine this console runs on, and its app name there — what it needs to update
  # itself (`vilice update`, decisions/update-is-rollback-pointed-forward.md). Chosen on
  # the Settings page, not set by an env var: an update changes only the image, so an env
  # var could only be set by the full deploy the update replaces.
  belongs_to :self_machine, class_name: "Machine", optional: true

  validates :self_app_name, format: { with: AppTemplate::NAME_FORMAT,
                                      message: "must start with a letter or digit, then letters, digits, dashes, and underscores" }

  def self.current
    first_or_create!
  end

  # This console's own entry in its box's status — its image, and its last update — or
  # nil when no machine is chosen, the box did not answer, or nothing there has the name.
  def self_on_box
    return unless self_machine

    MachineStatus.from(Vilice::Observe.status(self_machine)).apps.find { |a| a["name"] == self_app_name }
  end
end
