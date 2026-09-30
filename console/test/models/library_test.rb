require "test_helper"

# The App Library as a portable manifest — export/import round-trip, additive merge,
# and the deliberate omissions (labels stay local). See decisions/open/app-library.md.
class LibraryTest < ActiveSupport::TestCase
  test "export carries the app spec, env/secret schema, files, and versions" do
    app = AppTemplate.create!(name: "web", description: "Frontend", port: 8080, health: "/up",
                      env: [ { "key" => "LOG", "secret" => false },
                             { "key" => "TOKEN", "secret" => true } ],
                      secret_files: [ { "name" => "config", "path" => "/etc/web/config" } ])
    app.versions.create!(tag: "v1.0.0", image: "img@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf")
    v2 = app.versions.create!(tag: "v1.1.0", image: "img@sha256:ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7ee7e")
    app.set_latest!(v2)

    row = Library.export["apps"].sole
    assert_equal "web", row["name"]
    assert_equal 8080, row["port"]
    # Lean: the secret flag appears only when true.
    assert_equal [ { "key" => "LOG" }, { "key" => "TOKEN", "secret" => true } ], row["env"]
    assert_equal [ { "name" => "config", "path" => "/etc/web/config" } ], row["secret_files"]
    latest = row["versions"].find { |v| v["latest"] }
    assert_equal "v1.1.0", latest["tag"]
  end

  test "import normalizes env (missing secret reads false) and carries secret files" do
    Library.import("format" => 1, "apps" => [ {
      "name" => "web",
      "env" => [ { "key" => "LOG" }, { "key" => "TOKEN", "secret" => true } ],
      "secret_files" => [ { "name" => "config", "path" => "/etc/web/config" } ],
    } ])

    app = AppTemplate.find_by!(name: "web")
    assert_equal [ { "key" => "LOG", "secret" => false },
                   { "key" => "TOKEN", "secret" => true } ], app.env
    assert_equal %w[ TOKEN ], app.secret_keys
    assert_equal [ { "name" => "config", "path" => "/etc/web/config" } ], app.secret_files
  end

  test "labels are never exported — they are local, not part of the app's definition" do
    app = AppTemplate.create!(name: "web")
    app.labels.create!(key: "team", value: "payments")
    assert_not Library.export["apps"].sole.key?("labels")
  end

  test "round-trips an exported library back to an equivalent manifest" do
    app = AppTemplate.create!(name: "web", port: 8080)
    app.set_latest!(app.versions.create!(tag: "v1", image: "img@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    manifest = Library.export

    AppTemplate.destroy_all
    Library.import(manifest)

    assert_equal manifest, Library.export
  end

  test "import is additive — two libraries merge rather than replace" do
    Library.import("format" => 1, "apps" => [ { "name" => "abc-web" } ])
    Library.import("format" => 1, "apps" => [ { "name" => "acme-web" } ])
    assert_equal %w[ abc-web acme-web ], AppTemplate.order(:name).pluck(:name)
  end

  test "re-import upserts versions by tag and refreshes the image, deleting nothing" do
    app = AppTemplate.create!(name: "web")
    app.set_latest!(app.versions.create!(tag: "v1", image: "img@sha256:fcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdfcdf"))

    Library.import("format" => 1, "apps" => [ {
      "name" => "web",
      "versions" => [ { "tag" => "v1", "image" => "img@sha256:f98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98e" },
                      { "tag" => "v2", "image" => "img@sha256:47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f47f4", "latest" => true } ],
    } ])

    assert_equal "img@sha256:f98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98edf98e", app.versions.find_by(tag: "v1").image
    assert_equal "v2", app.reload.latest_version.tag
    assert_equal 2, app.versions.count
  end

  test "a re-import without a latest flag leaves the chosen latest alone" do
    app = AppTemplate.create!(name: "web")
    app.versions.create!(tag: "v1", image: "img@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    v2 = app.versions.create!(tag: "v2", image: "img@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    app.set_latest!(v2)

    Library.import("format" => 1, "apps" => [ {
      "name" => "web", "versions" => [ { "tag" => "v1", "image" => "img@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } ],
    } ])

    assert_equal "v2", app.reload.latest_version.tag
  end

  test "an unknown format is refused" do
    assert_raises(Library::UnsupportedFormat) { Library.import("format" => 99, "apps" => []) }
  end

  test "fetch refuses a non-http url (no file:// or ftp:// reach)" do
    assert_raises(Library::UnsupportedFormat) { Library.fetch("file:///etc/passwd") }
    assert_raises(Library::UnsupportedFormat) { Library.fetch("ftp://example.com/lib.yml") }
  end

  test "fetch retrieves and parses a manifest over http" do
    body = { "format" => 1, "apps" => [ { "name" => "served" } ] }.to_yaml
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      client = server.accept
      client.gets("\r\n\r\n") # consume the request headers (GET, no body)
      client.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    end

    data = Library.fetch("http://127.0.0.1:#{server.addr[1]}/lib.yml")
    assert_equal "served", data["apps"].first["name"]
  ensure
    thread&.join(2)
    server&.close
  end

  # The manifest is the interchange format, so a field it drops is a field that vanishes
  # on the way out and back. argv stays a list — flattening it to a string would export a
  # shell command the box has no shell to run.
  test "a release command survives an export/import round trip as argv" do
    app = AppTemplate.create!(name: "web", port: 8080, release: [ "bin/rails", "db:migrate" ])
    app.versions.create!(tag: "v1", image: "img@sha256:#{'a' * 64}")

    manifest = Library.export
    Version.delete_all
    AppTemplate.delete_all
    Library.import(manifest)

    assert_equal [ "bin/rails", "db:migrate" ], AppTemplate.find_by(name: "web").release
  end

  # Absent means "leave it alone", the same rule every other field follows here.
  test "a manifest without a release command does not clear one" do
    AppTemplate.create!(name: "web", release: [ "bin/rails", "db:migrate" ])

    Library.import({ "format" => 1, "apps" => [ { "name" => "web", "port" => 3000 } ] })

    assert_equal [ "bin/rails", "db:migrate" ], AppTemplate.find_by(name: "web").release
  end

  test "accessories survive an export/import round trip in the box's own shape" do
    db = { "name" => "db", "image" => "postgres@sha256:#{'b' * 64}",
           "env" => { "POSTGRES_DB" => "app" }, "secrets" => [ "POSTGRES_PASSWORD" ],
           "volumes" => [ "db-data:/var/lib/postgresql/data" ] }
    app = AppTemplate.create!(name: "web", accessories: [ db ])
    app.versions.create!(tag: "v1", image: "img@sha256:#{'a' * 64}")

    manifest = Library.export
    Version.delete_all
    AppTemplate.delete_all
    Library.import(manifest)

    assert_equal [ db ], AppTemplate.find_by(name: "web").accessories
  end

  test "processes survive an export/import round trip as argv" do
    worker = { "name" => "worker", "command" => [ "bin/jobs" ] }
    app = AppTemplate.create!(name: "web", processes: [ worker ])
    app.versions.create!(tag: "v1", image: "img@sha256:#{'a' * 64}")

    manifest = Library.export
    Version.delete_all
    AppTemplate.delete_all
    Library.import(manifest)

    assert_equal [ worker ], AppTemplate.find_by(name: "web").processes
  end
end
