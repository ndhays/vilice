class SettingsController < ApplicationController
  def show
    @user          = Current.user
    @setting       = Setting.current
    @project_count = Project.count
    @machine_count = Machine.count
    @shared_count  = Machine.shared.count
    @version       = StewardConsole::VERSION
  end

  # Toggle fleet policy — a recorded control-plane act.
  def update
    setting = Setting.current
    Setting.transaction do
      setting.update!(settings_params)
      restricted = setting.apps_library_only
      Event.record!(actor: Current.user.email_address, action: restricted ? "restricted" : "opened",
                    summary: "apps #{restricted ? 'to' : 'beyond'} App Library templates")
    end
    redirect_to settings_path, notice: "Settings updated."
  end

  # Appearance — this operator's own theme and mode. Not a recorded act: it changes
  # nothing about the fleet and touches no box, so it stays off the record, the same
  # line the observe side is on. Either field may arrive alone (the rail's toggle
  # sends only `mode`).
  def appearance
    user = Current.user
    if user.update(params.permit(:theme, :mode).compact_blank)
      redirect_back fallback_location: settings_path
    else
      redirect_back fallback_location: settings_path,
                    alert: user.errors.full_messages.to_sentence
    end
  end

  # Change the signed-in user's own password — verify the current one, then set the
  # new (with confirmation). The current session stays valid; this isn't the reset
  # flow (which is for users locked out).
  def change_password
    user = Current.user

    if !user.authenticate(params[:current_password])
      redirect_to settings_path, alert: "Current password is incorrect."
    elsif params[:password].blank?
      redirect_to settings_path, alert: "New password can't be blank."
    elsif user.update(params.permit(:password, :password_confirmation))
      redirect_to settings_path, notice: "Password changed."
    else
      redirect_to settings_path,
        alert: user.errors.full_messages.to_sentence.presence || "Couldn't change the password."
    end
  end

  # Dev tool — wipe all fleet data for a clean slate. Keeps your login + the Setting.
  # Refused outside development/test (it never touches a real fleet). delete_all is
  # used deliberately: it skips callbacks (Event is otherwise append-only) and runs
  # child-before-parent so foreign keys hold.
  def destroy_data
    return redirect_to settings_path, alert: "Erase is disabled outside development." unless Rails.env.local?

    ActiveRecord::Base.transaction do
      [ Placement, Snapshot, Event, Label, App, Version, ProjectMachine,
        AppTemplate, Machine, Project ].each(&:delete_all)
    end
    redirect_to settings_path, notice: "All fleet data erased."
  end

  private

  def settings_params
    params.require(:setting).permit(:apps_library_only)
  end
end
