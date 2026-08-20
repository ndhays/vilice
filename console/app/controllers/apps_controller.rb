# The App Library — the admin's curated directory of installable app definitions
# (decisions/open/app-library.md). Curating the library is a Steward Console own-record
# act, so each change is attributed and recorded in the same transaction (the
# record is append-only; mirrors projects#star and the label editor).
class AppsController < ApplicationController
  before_action :set_app, only: %i[ show edit update destroy ]

  def index
    @q    = params[:q].to_s.strip
    @apps = App.search(@q).order(:name).includes(:latest_version, :versions, :labels)
  end

  def show
    @versions = @app.versions.newest_first
    @version  = @app.versions.new
  end

  def new
    @app = App.new
  end

  def edit; end

  def create
    @app = App.new(app_params)
    if save_recording(@app, "added", "#{@app.name} to the App Library")
      redirect_to @app, notice: "Added #{@app.name}. Add a version to install it."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @app.assign_attributes(app_params)
    if save_recording(@app, "edited", @app.name)
      redirect_to @app, notice: "Updated #{@app.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    App.transaction do
      @app.destroy!
      record("removed", "#{@app.name} from the App Library")
    end
    redirect_to apps_path, notice: "Removed #{@app.name} from the App Library."
  end

  # The library as a portable manifest — a YAML file to share, version, or seed
  # another Steward Console from. The DB stays the store; this is the interchange shape.
  def export
    send_data Library.export.to_yaml, filename: "console-library.yml",
              type: "application/x-yaml", disposition: "attachment"
  end

  # Merge a manifest in — from an uploaded file or a URL (the marketplace path).
  # Additive (Library.import upserts, deletes nothing), so two libraries can be
  # imported and coexist. One recorded act names every app it touched in `detail` —
  # legible without a row per app.
  def import
    if params[:url].present?
      source = params[:url]
      data   = Library.fetch(source)
    else
      file   = params.require(:file)
      source = file.original_filename
      data   = YAML.safe_load(file.read)
    end

    apps  = Library.import(data)
    count = apps.size
    record("imported", "#{count} #{'app'.pluralize(count)} from #{source}",
           detail: apps.map(&:name).sort.join(", ")) if count.positive?
    redirect_to apps_path, notice: "Imported #{count} #{'app'.pluralize(count)}."
  rescue Library::UnsupportedFormat => e
    redirect_to apps_path, alert: "Unsupported library (#{e.message})."
  rescue Psych::Exception, KeyError, ActionController::ParameterMissing,
         ActiveRecord::RecordInvalid, URI::InvalidURIError, SocketError,
         SystemCallError, Timeout::Error => e
    redirect_to apps_path, alert: "Couldn't import that library: #{e.message}"
  end

  # Bulk curation — the deliberate, recorded counterweight to additive import.
  def remove_selected
    apps  = App.where(id: Array(params[:ids]).reject(&:blank?))
    names = apps.order(:name).pluck(:name)
    if names.any?
      App.transaction do
        apps.destroy_all
        record("removed", "#{names.size} #{'app'.pluralize(names.size)} from the App Library",
               detail: names.join(", "))
      end
      redirect_to apps_path, notice: "Removed #{names.size} #{'app'.pluralize(names.size)}."
    else
      redirect_to apps_path, alert: "No apps selected."
    end
  end

  private

  def set_app
    @app = App.find(params[:id])
  end

  # One accessory row → the shape the box's spec uses, so the deploy envelope is a copy
  # and not a translation. Volumes and env are typed as lines because that is how people
  # think about them; secrets are names on one line, since values never live here.
  #
  # Nothing is coerced beyond splitting: a malformed image or an escaping volume is the
  # model's to refuse, with a sentence, rather than something silently dropped here.
  def accessory_from(row)
    name = row[:name].to_s.strip
    return nil if name.blank?

    env = lines(row[:env]).to_h { |l| k, _, v = l.partition("="); [ k.strip, v.strip ] }
    { "name"    => name,
      "image"   => row[:image].to_s.strip,
      "env"     => env.presence,
      "secrets" => row[:secrets].to_s.split.presence,
      "volumes" => lines(row[:volumes]).presence }.compact
  end

  def lines(text) = text.to_s.split("\n").map(&:strip).reject(&:blank?)

  def app_params
    attrs = params.require(:app).permit(:name, :port, :health, :description).to_h

    # The release command is typed as one line and stored as **argv**, because argv is
    # what the box execs — it never sees a shell, so a multi-step release belongs in a
    # script inside the image where the digest covers what it does. Splitting on
    # whitespace is the whole translation: anything needing more is asking for a shell,
    # and this is where that is declined rather than quietly granted.
    #
    # Keyed on the field being present, for the same reason the editors below are: the
    # details form posts to this action too and carries no release field, and there
    # "leave it alone" is right.
    attrs["release"] = params[:app][:release_line].to_s.split if params[:app].key?(:release_line)

    # The env / secret-file editors post indexed rows. Build the stored lists by hand
    # (names only — no values), dropping blank rows and coercing the secret checkbox.
    #
    # `inputs_form` is why the rows are read at all. Removing the last row leaves the
    # editor with no `env_rows` / `secret_file_rows` key to post, and treating an
    # absent key as "leave it alone" meant the last variable or file could not be
    # deleted — it came back on every save. But the *details* form (name, port, health)
    # posts to this same action and carries neither key, and there "leave it alone" is
    # exactly right. The marker separates the two: absent rows mean **empty** only when
    # the editor is the thing that was submitted.
    if params.dig(:app, :inputs_form)
      attrs["env"] = Array(params.dig(:app, :env_rows)&.values).filter_map { |r|
        key = r[:key].to_s.strip
        { "key" => key, "secret" => r[:secret] == "1" } if key.present?
      }
      attrs["secret_files"] = Array(params.dig(:app, :secret_file_rows)&.values).filter_map { |r|
        name = r[:name].to_s.strip
        { "name" => name, "path" => r[:path].to_s.strip } if name.present?
      }
      attrs["accessories"] = Array(params.dig(:app, :accessory_rows)&.values).filter_map { |r|
        accessory_from(r)
      }
      attrs["processes"] = Array(params.dig(:app, :process_rows)&.values).filter_map { |r|
        name = r[:name].to_s.strip
        # Typed as a line, stored as argv — the box execs it and never sees a shell, the
        # same translation the release command gets and for the same reason.
        { "name" => name, "command" => r[:command].to_s.split } if name.present?
      }
    end
    attrs
  end

  def save_recording(app, action, summary)
    App.transaction do
      app.save!
      record(action, summary)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def record(action, summary, detail: nil)
    Event.record!(actor: Current.user.email_address, action: action, summary: summary, detail: detail)
  end
end
