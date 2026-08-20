# The App Library as a portable manifest. The DB is the runtime store; this is the
# interchange format — a plain Hash ready for YAML, shareable and seedable, and the
# shape a marketplace would publish (applibrary.agoraforge.org). See
# decisions/open/app-library.md.
#
# Two deliberate choices live here:
#   - Import is *additive*: apps upsert by name, versions by tag (image refreshed);
#     nothing is ever deleted. Pruning is a separate, recorded act (apps#remove_selected).
#   - Labels are *omitted*: they are the admin's local organization, not part of an
#     app's official definition. A library never carries or dictates them.
require "net/http"

module Library
  FORMAT = 1

  class UnsupportedFormat < StandardError; end

  # The whole library as a manifest Hash. `compact` keeps the file lean — absent
  # fields simply don't appear.
  def self.export
    {
      "format" => FORMAT,
      "apps" => App.order(:name).includes(:versions).map { |app| app_to_h(app) },
    }
  end

  # Merge a manifest into the library. Returns the App records touched, in file
  # order, so the caller can record one act naming them all.
  def self.import(data)
    raise UnsupportedFormat, data["format"].inspect unless data.is_a?(Hash) && data["format"] == FORMAT

    Array(data["apps"]).map { |row| import_app(row) }
  end

  # Fetch and parse a manifest from a URL — the marketplace path (import-from-URL).
  # http(s) only, short timeouts, a few redirects. Admin-only and admin-trusted;
  # a future hardening could refuse private address ranges (SSRF).
  def self.fetch(url, redirects: 3)
    raise UnsupportedFormat, "too many redirects" if redirects.negative?
    uri = URI.parse(url)
    raise UnsupportedFormat, "URL must be http or https" unless uri.is_a?(URI::HTTP) && uri.host

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: 5, read_timeout: 5) { |http| http.get(uri.request_uri) }
    case res
    when Net::HTTPSuccess     then YAML.safe_load(res.body)
    when Net::HTTPRedirection then fetch(res["location"], redirects: redirects - 1)
    else raise UnsupportedFormat, "fetch failed (HTTP #{res.code})"
    end
  end

  def self.app_to_h(app)
    {
      "name"         => app.name,
      "description"  => app.description,
      "port"         => app.port,
      "health"       => app.health,
      # Env entries carry the key and the secret flag (omit it when false, to stay lean).
      "env"          => app.env.map { |e|
        e["secret"] ? { "key" => e["key"], "secret" => true } : { "key" => e["key"] }
      }.presence,
      "secret_files" => app.secret_files.presence,
      # argv, so it round-trips as a list. A manifest that flattened it to a string would
      # be exporting a shell command the box has no shell to run.
      "release"      => app.release.presence,
      # Round-trips as-is: the stored shape is the box's spec shape, so a manifest that
      # reshaped it would be inventing a second definition to keep in step.
      "accessories"  => app.accessories.presence,
      "processes"    => app.processes.presence,
      "versions"     => app.versions.newest_first.map { |v|
        { "tag" => v.tag, "image" => v.image, "latest" => v.latest }.compact
      }.presence,
    }.compact
  end

  # Upsert one app and its versions. Only the fields the manifest carries are
  # written — an absent key never clears an existing value (additive, true to the
  # "nothing is deleted" rule).
  def self.import_app(row)
    App.transaction do
      app = App.find_or_initialize_by(name: row.fetch("name"))
      attrs = row.slice("description", "port", "health")
      attrs["env"] = normalize_env(row["env"]) if row["env"].present?
      attrs["secret_files"] = Array(row["secret_files"]) if row["secret_files"].present?
      attrs["release"] = Array(row["release"]) if row["release"].present?
      attrs["accessories"] = Array(row["accessories"]) if row["accessories"].present?
      attrs["processes"] = Array(row["processes"]) if row["processes"].present?
      app.update!(attrs)

      versions = Array(row["versions"])
      versions.each do |v|
        app.versions.find_or_initialize_by(tag: v.fetch("tag")).update!(image: v.fetch("image"))
      end

      # Honour the one-latest invariant ourselves: trust the manifest's flag, not
      # its order. With no flag, set a latest only when the app has none yet — a
      # re-import never disturbs a latest you chose locally.
      if (flagged = versions.find { |v| v["latest"] })
        app.set_latest!(app.versions.find_by!(tag: flagged["tag"]))
      elsif !app.versions.exists?(latest: true) && (first = app.versions.order(:id).first)
        app.set_latest!(first)
      end

      app
    end
  end

  # Coerce manifest env entries to the stored shape, so an omitted `secret` reads as
  # false. (Both the lean export and a hand-written manifest round-trip through here.)
  def self.normalize_env(list)
    Array(list).map { |e| { "key" => e["key"], "secret" => !!e["secret"] } }
  end
end
