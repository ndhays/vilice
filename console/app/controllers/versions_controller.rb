# Releases of a library AppTemplate. Each version is a (tag, image) pair; exactly one is
# `latest` (the install default). Adding, removing, and promoting a version are
# control-plane own-record acts, recorded with the change in one transaction.
class VersionsController < ApplicationController
  before_action :set_app

  def create
    first       = @app_template.versions.empty? # the first version is always latest
    @version    = @app_template.versions.new(version_params)
    make_latest = first || ActiveModel::Type::Boolean.new.cast(params[:make_latest])

    ok = false
    AppTemplate.transaction do
      ok = @version.save
      raise ActiveRecord::Rollback unless ok
      @app_template.set_latest!(@version) if make_latest
      record("added", "#{@app_template.name} #{@version.tag}")
    end

    if ok
      redirect_to @app_template, notice: "Added #{@app_template.name} #{@version.tag}."
    else
      @versions = @app_template.versions.newest_first
      render "app_templates/show", status: :unprocessable_entity
    end
  end

  # Look the digest up and put it in the field — then stop. **Resolution is a read;
  # pinning is a decision** (app/services/registry.rb), so this saves nothing and
  # records nothing: it hands back a filled-in form, and adding the version is still
  # the same press it always was. The two steps are deliberately visible.
  def resolve
    @version  = @app_template.versions.new(version_params)
    @versions = @app_template.versions.newest_first

    begin
      @version.image = Registry.pin(@version.image)
      flash.now[:notice] = "Resolved to #{@version.image}. Nothing is saved yet."
    rescue Registry::Error => e
      flash.now[:alert] = e.message
    end

    render "app_templates/show"
  end

  def latest
    version = @app_template.versions.find(params[:id])
    @app_template.set_latest!(version)
    record("set", "#{@app_template.name} latest to #{version.tag}")
    redirect_to @app_template, notice: "#{version.tag} is now latest."
  end

  def destroy
    version = @app_template.versions.find(params[:id])
    AppTemplate.transaction do
      version.destroy!
      record("removed", "#{@app_template.name} #{version.tag}")
    end
    redirect_to @app_template, notice: "Removed #{@app_template.name} #{version.tag}."
  end

  private

  def set_app
    @app_template = AppTemplate.find(params[:app_template_id])
  end

  def version_params
    params.require(:version).permit(:tag, :image)
  end

  def record(action, summary)
    Event.record!(actor: Current.user.email_address, action: action, summary: summary)
  end
end
