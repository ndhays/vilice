class SettingsController < ApplicationController
  def show
    @user          = Current.user
    @setting       = Setting.current
    @project_count = Project.count
    @machine_count = Machine.count
    @shared_count  = Machine.shared.count
    @version       = ViliceConsole::VERSION
    # This console on its own box: the machines it could be, and what that box reports
    # about it (the cached status read, the same one the machine page uses).
    @self_machines = Machine.order(:name)
    @self_on_box   = @setting.self_on_box
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

  # Where this console runs — the machine and its app name there. A recorded act: it
  # decides which box the Update button below acts on.
  def self_box
    setting = Setting.current
    machine = Machine.find_by(id: params[:self_machine_id].presence)
    Setting.transaction do
      setting.update!(self_machine: machine, self_app_name: params[:self_app_name].to_s.strip.presence || "console")
      Event.record!(actor: Current.user.email_address, action: machine ? "set" : "cleared",
                    machine: machine,
                    summary: machine ? "this console runs as #{setting.self_app_name} on #{machine.name}" : "which box this console runs on")
    end
    redirect_to settings_path(anchor: "this-console"), notice: "Saved where this console runs."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_path(anchor: "this-console"), alert: e.record.errors.full_messages.to_sentence
  end

  # Update this console to a new image, on its own box. `vilice update` re-deploys the
  # spec the box holds with only the image changed — the console's secrets stay where
  # they are, and none is sent — and runs in the background, because this process is the
  # one being replaced. The new version, once healthy, is what answers the next request.
  def update_console
    setting = Setting.current
    machine = setting.self_machine
    image   = params[:image].to_s.strip

    if machine.nil?
      return redirect_to settings_path(anchor: "this-console"), alert: "Choose the machine this console runs on first."
    elsif !machine.operate?
      return redirect_to settings_path(anchor: "this-console"), alert: "#{machine.name}'s key is observe-only; updating needs operate."
    elsif !image.match?(Setting::IMAGE_FORMAT)
      return redirect_to settings_path(anchor: "this-console"),
                         alert: "Give the image pinned by digest — ref@sha256: and 64 hex characters, as make push prints it."
    end

    outcome = Vilice::Mutate.run(
      machine, "update #{setting.self_app_name} --image #{image} --json",
      actor: Current.user.email_address, action: "updated",
      summary: "#{setting.self_app_name} on #{machine.name} to #{image[/sha256:\h{12}/]}"
    )
    if outcome[:result][:ok]
      redirect_to settings_path(anchor: "this-console"),
                  notice: "Updating. The new version takes over once it passes its health check — reload in a minute."
    else
      redirect_to settings_path(anchor: "this-console"), alert: outcome[:result][:error]
    end
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
