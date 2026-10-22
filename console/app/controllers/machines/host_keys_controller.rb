# The box's host key — the one that proves the console reached the box it meant to.
#
# The console pins it on the Machine and refuses a box that answers with another
# (HostKey). A rebuilt box does exactly that, and so does something else answering at
# its address; only a person can tell them apart. This page puts the two fingerprints
# side by side, and trusting the new one is an act, recorded with both.
# See decisions/host-keys-are-pinned-on-the-machine.md.
class Machines::HostKeysController < ApplicationController
  before_action :set_machine

  def show
    @offered = HostKey.scan(@machine)
  end

  # Trust what the box answers with now — but only if it is still the key the person
  # looked at. The fingerprint they saw rides the form; the box is asked again, and a
  # different answer is refused rather than trusted unseen.
  def update
    offered = HostKey.scan(@machine)
    seen = params[:fingerprint].to_s

    if offered.nil?
      redirect_to machine_host_key_path(@machine), alert: "#{@machine.name} did not answer with a key. Nothing changed."
    elsif SshKeypair.fingerprint(offered) != seen
      redirect_to machine_host_key_path(@machine),
                  alert: "#{@machine.name} answers with a different key from the one you were shown. Nothing changed — compare again."
    else
      replace(offered)
      redirect_to settings_machine_path(@machine, anchor: "host-key"), notice: "Trusted #{@machine.name}'s new key."
    end
  end

  private

  def replace(offered)
    before = @machine.ssh_host_key_fingerprint
    Machine.transaction do
      @machine.update!(ssh_host_key: offered, ssh_host_key_trusted_at: Time.current)
      summary = before ? "#{@machine.name}: #{SshKeypair.fingerprint(offered)}, replacing #{before}" :
                         "#{@machine.name}: #{SshKeypair.fingerprint(offered)}"
      Event.record!(actor: Current.user.email_address, action: "trusted host key",
                    machine: @machine, summary: summary)
    end
  end

  def set_machine = @machine = Machine.find(params[:machine_id])
end
