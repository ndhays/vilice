require "test_helper"

class AppTest < ActiveSupport::TestCase
  test "a name is required and unique" do
    App.create!(name: "nginx")
    assert_not App.new.valid?                               # no name
    dup = App.new(name: "nginx")
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  test "name must be box-safe — [A-Za-z0-9_-], first character alphanumeric" do
    assert App.new(name: "my-cool_app1").valid?
    bad = App.new(name: "My Cool App")
    assert_not bad.valid?
    assert_includes bad.errors[:name], "must start with a letter or digit, then letters, digits, dashes, and underscores"
    assert_not App.new(name: "web/edge").valid?               # no slashes (it's a filename on the box)
    assert_not App.new(name: "-web").valid?                   # a leading dash reads as a flag on the box
    assert_not App.new(name: "_web").valid?                   # same rule, one charset
  end

  test "port must be in the box's 1024–65535 range, or blank" do
    assert App.new(name: "a", port: nil).valid?               # blank = no app default
    assert App.new(name: "a", port: 8080).valid?
    assert_not App.new(name: "a", port: 80).valid?            # below the unprivileged floor
    assert_not App.new(name: "a", port: 70000).valid?
  end

  test "health must start with a slash, or be blank" do
    assert App.new(name: "a", health: nil).valid?
    assert App.new(name: "a", health: "/up").valid?
    app = App.new(name: "a", health: "up")
    assert_not app.valid?
    assert_includes app.errors[:health], "must start with /"
  end

  test "latest_version is the one flagged latest, and set_latest! keeps exactly one" do
    app = App.create!(name: "web")
    v1 = app.versions.create!(tag: "v1", image: "img@sha256:1111111111111111111111111111111111111111111111111111111111111111")
    app.set_latest!(v1)
    assert_equal v1, app.reload.latest_version

    v2 = app.versions.create!(tag: "v2", image: "img@sha256:2222222222222222222222222222222222222222222222222222222222222222")
    app.set_latest!(v2)
    assert_equal v2, app.reload.latest_version
    assert_equal 1, app.versions.where(latest: true).count   # only one latest
  end

  test "search matches name substring and key=value / bare-key labels" do
    web = App.create!(name: "acme-web")
    web.labels.create!(key: "team", value: "payments")
    App.create!(name: "billing")

    assert_equal [ web ], App.search("acme").to_a            # name substring
    assert_equal [ web ], App.search("team=payments").to_a   # label selector
    assert_equal [ web ], App.search("team").to_a            # bare key
    assert_equal 2, App.search("").count                     # blank = all
  end

  test "env is a list of {key, secret}; bad names and duplicates are refused" do
    assert App.new(name: "a", env: []).valid?
    assert App.new(name: "a", env: [ { "key" => "PASSWORD", "secret" => true } ]).valid?

    bad = App.new(name: "a", env: [ { "key" => "has space" } ])
    assert_not bad.valid?

    dup = App.new(name: "a", env: [ { "key" => "X" }, { "key" => "X", "secret" => true } ])
    assert_not dup.valid?
  end

  test "secret_keys are the secret env vars; env_keys are all of them" do
    app = App.new(name: "a", env: [ { "key" => "LOG" }, { "key" => "TOKEN", "secret" => true } ])
    assert_equal %w[ LOG TOKEN ], app.env_keys
    assert_equal %w[ TOKEN ], app.secret_keys
  end

  test "secret files need a name and an absolute path, and can't clash with an env var" do
    assert App.new(name: "a", secret_files: [ { "name" => "config", "path" => "/etc/x" } ]).valid?

    relative = App.new(name: "a", secret_files: [ { "name" => "config", "path" => "etc/x" } ])
    assert_not relative.valid?

    clash = App.new(name: "a", env: [ { "key" => "X" } ],
                              secret_files: [ { "name" => "X", "path" => "/x" } ])
    assert_not clash.valid?
    assert_includes clash.errors[:secret_files].join, "both an env var and a file"
  end

  test "destroying an app takes its versions and labels with it" do
    app = App.create!(name: "web")
    app.versions.create!(tag: "v1", image: "ghcr.io/acme/app@sha256:abababababababababababababababababababababababababababababababab")
    app.labels.create!(key: "x")
    assert_difference [ -> { Version.count }, -> { Label.count } ], -1 do
      app.destroy
    end
  end
end
