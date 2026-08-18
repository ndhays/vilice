require "test_helper"

# Resolving a tag to a digest. The rule the box enforces does not move — a release is
# still pinned — this only removes the part where a person copies 64 hex characters by
# hand. See app/services/registry.rb: resolution is a read, pinning is a decision.
class RegistryTest < ActiveSupport::TestCase
  # The parse is where the awkward cases live, and it is pure, so it is cheap to be
  # exhaustive about. The rule is the one container runtimes use: the first segment is a
  # registry only if it looks like a host.
  test "a bare name is a Docker Hub library image at :latest" do
    assert_equal [ "docker.io", "library/nginx", "latest" ], Registry.parse("nginx")
    assert_equal [ "docker.io", "library/redis", "7" ],      Registry.parse("redis:7")
  end

  test "a two-part name with no dot is a Docker Hub user repository, not a registry" do
    assert_equal [ "docker.io", "acme/web", "latest" ], Registry.parse("acme/web")
    assert_equal [ "docker.io", "acme/web", "v1" ],     Registry.parse("acme/web:v1")
  end

  test "a first segment that looks like a host is the registry" do
    assert_equal [ "ghcr.io", "acme/web", "v1" ], Registry.parse("ghcr.io/acme/web:v1")
    assert_equal [ "quay.io", "team/app/sub", "latest" ], Registry.parse("quay.io/team/app/sub")
    assert_equal [ "localhost", "dev", "edge" ], Registry.parse("localhost/dev:edge")
  end

  # The one that trips naive splitting: a colon can be a registry's port or a tag, and
  # only its position relative to the last slash says which.
  test "a port in the registry is not mistaken for a tag" do
    assert_equal [ "reg.example.com:5000", "team/app", "v2" ],
                 Registry.parse("reg.example.com:5000/team/app:v2")
    assert_equal [ "reg.example.com:5000", "team/app", "latest" ],
                 Registry.parse("reg.example.com:5000/team/app")
  end

  test "an already-pinned reference is handed back untouched, not re-resolved" do
    pinned = "ghcr.io/acme/web@sha256:#{'a' * 64}"

    # No network seam is stubbed here on purpose: if this reached out, the test would
    # fail. Re-asking would be a chance for the answer to differ from the one in hand.
    assert_equal pinned, Registry.pin(pinned)
  end

  test "an empty reference asks for one rather than reaching out" do
    error = assert_raises(Registry::Error) { Registry.pin("  ") }
    assert_match(/Type an image first/, error.message)
  end

  # What gets stored is the full name, not the short one typed. `redis:7` and
  # `docker.io/library/redis:7` are the same image, and only one of them says so.
  test "pin normalises to the full name so the registry is never implied" do
    digest = "sha256:#{'b' * 64}"
    with_resolve(digest) do
      assert_equal "docker.io/library/redis@#{digest}", Registry.pin("redis:7")
      assert_equal "ghcr.io/acme/web@#{digest}", Registry.pin("ghcr.io/acme/web:v1")
    end
  end

  # A registry that wants a credential is a stop, not a prompt. The console holds no
  # registry logins by design (decisions/registry-credentials.md) and this is not the
  # feature that changes that.
  test "an authenticated registry says so and points at the box" do
    error = assert_raises(Registry::Error) { resolve_against("401 Unauthorized") }
    assert_match(/wants a credential/, error.message)
    assert_match(/steward registry-login/, error.message)
    assert_match(/Paste the digest/, error.message)
  end

  test "an unknown tag names the tag rather than the status code" do
    error = assert_raises(Registry::Error) { resolve_against("404 Not Found") }
    assert_match(%r{No tag v1 at 127\.0\.0\.1}, error.message)
  end

  test "a success with no digest header is refused rather than guessed at" do
    error = assert_raises(Registry::Error) { resolve_against("200 OK") }
    assert_match(/without a digest/, error.message)
  end

  test "a reachable registry hands back the digest it reports" do
    digest = "sha256:#{'c' * 64}"
    assert_equal digest, resolve_against("200 OK", "Docker-Content-Digest: #{digest}")
  end

  test "a registry that cannot be reached says which host" do
    # Port 1 with nothing on it — a connection refused, not a timeout, so it is quick.
    error = assert_raises(Registry::Error) { Registry.resolve("127.0.0.1:1", "acme/web", "v1") }
    assert_match(/Couldn't reach 127\.0\.0\.1/, error.message)
  end

  private

  # Swap the network half out and put it back. Minitest 6 dropped `minitest/mock`, and
  # this is three lines rather than a dependency.
  def with_resolve(digest)
    original = Registry.method(:resolve)
    Registry.define_singleton_method(:resolve) { |*| digest }
    yield
  ensure
    Registry.define_singleton_method(:resolve, original)
  end

  # A one-shot registry on loopback. `scheme` sends loopback over plain http — which is
  # how container tooling already treats a local registry, and the only way to run one
  # without a certificate.
  def resolve_against(status, *headers)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      client = server.accept
      client.gets("\r\n\r\n")
      client.write(([ "HTTP/1.1 #{status}" ] + headers + [ "Content-Length: 0", "Connection: close" ])
                     .join("\r\n") + "\r\n\r\n")
      client.close
    rescue IOError, Errno::ECONNRESET
      nil
    end

    Registry.resolve("127.0.0.1:#{server.addr[1]}", "acme/web", "v1")
  ensure
    thread&.join(2)
    server&.close
  end
end
