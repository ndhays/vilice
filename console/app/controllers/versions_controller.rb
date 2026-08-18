# Releases of a library App. Each version is a (tag, image) pair; exactly one is
# `latest` (the install default). Adding, removing, and promoting a version are
# control-plane own-record acts, recorded with the change in one transaction.
class VersionsController < ApplicationController
  before_action :set_app

  def create
    first       = @app.versions.empty? # the first version is always latest
    @version    = @app.versions.new(version_params)
    make_latest = first || ActiveModel::Type::Boolean.new.cast(params[:make_latest])

    ok = false
    App.transaction do
      ok = @version.save
      raise ActiveRecord::Rollback unless ok
      @app.set_latest!(@version) if make_latest
      record("added", "#{@app.name} #{@version.tag}")
    end

    if ok
      redirect_to @app, notice: "Added #{@app.name} #{@version.tag}."
    else
      @versions = @app.versions.newest_first
      render "apps/show", status: :unprocessable_entity
    end
  end

  # Look the digest up and put it in the field — then stop. **Resolution is a read;
  # pinning is a decision** (app/services/registry.rb), so this saves nothing and
  # records nothing: it hands back a filled-in form, and adding the version is still
  # the same press it always was. The two steps are deliberately visible.
  def resolve
    @version  = @app.versions.new(version_params)
    @versions = @app.versions.newest_first

    begin
      @version.image = Registry.pin(@version.image)
      flash.now[:notice] = "Resolved to #{@version.image}. Nothing is saved yet."
    rescue Registry::Error => e
      flash.now[:alert] = e.message
    end

    render "apps/show"
  end

  def latest
    version = @app.versions.find(params[:id])
    @app.set_latest!(version)
    record("set", "#{@app.name} latest to #{version.tag}")
    redirect_to @app, notice: "#{version.tag} is now latest."
  end

  def destroy
    version = @app.versions.find(params[:id])
    App.transaction do
      version.destroy!
      record("removed", "#{@app.name} #{version.tag}")
    end
    redirect_to @app, notice: "Removed #{@app.name} #{version.tag}."
  end

  private

  def set_app
    @app = App.find(params[:app_id])
  end

  def version_params
    params.require(:version).permit(:tag, :image)
  end

  def record(action, summary)
    Event.record!(actor: Current.user.email_address, action: action, summary: summary)
  end
end
