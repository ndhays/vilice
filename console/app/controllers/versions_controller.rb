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
      record("added version", "Added #{@app.name} #{@version.tag}")
    end

    if ok
      redirect_to @app, notice: "Added #{@app.name} #{@version.tag}."
    else
      @versions = @app.versions.newest_first
      render "apps/show", status: :unprocessable_entity
    end
  end

  def latest
    version = @app.versions.find(params[:id])
    @app.set_latest!(version)
    record("set latest version", "Set #{@app.name} latest to #{version.tag}")
    redirect_to @app, notice: "#{version.tag} is now latest."
  end

  def destroy
    version = @app.versions.find(params[:id])
    App.transaction do
      version.destroy!
      record("removed version", "Removed #{@app.name} #{version.tag}")
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
