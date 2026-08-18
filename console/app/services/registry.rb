require "net/http"

# Ask a registry what digest a tag points at *right now*.
#
# The box refuses an unpinned image (`steward/internal/app/deploy.go`), and `Version`
# mirrors that refusal so it fails where you type it. The only unpleasant part of that
# rule is finding 64 hex characters by hand, and removing that friction is the console's
# job — softening the rule is not. So:
#
#   **Resolution is a read; pinning is a decision.**
#
# This looks a tag up once and hands the answer back for a person to save. Nothing
# re-resolves it afterwards. A tag means something different tomorrow, and a release that
# quietly followed it would make "what was running" unanswerable — which is the whole
# reason the pin exists (decisions/drift-is-surfaced-never-closed.md has the same shape:
# the console shows you the new thing, a person decides).
#
# **Public registries only, on purpose.** A private one needs a credential, and that
# credential lives on the box (decisions/registry-credentials.md) exactly so the console
# never holds pull access to your images. When a registry asks for authentication this
# says so and stops, rather than growing somewhere to put a password — a new secret in
# the control plane is a raised ceiling (decisions/ceiling-is-the-machine.md), and this
# convenience is not worth one.
#
# A lookup is a read, so it writes no record (decisions/a-sample-is-not-an-act.md). The
# act is saving the version, and that is recorded where it always was.
module Registry
  Error = Class.new(StandardError)

  # Both manifest shapes and both index shapes: a multi-arch tag answers with an index,
  # and the index's own digest is the right pin — it is what a runtime resolves from.
  ACCEPT = [
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json"
  ].join(", ").freeze

  DEFAULT_HOST = "docker.io".freeze
  # Docker Hub's catalogue name and its API endpoint are different hosts. We keep the
  # first in what we store, because that is the name people read and type.
  DOCKER_HUB_API = "registry-1.docker.io".freeze
  DIGEST_HEADER  = "docker-content-digest".freeze
  TIMEOUT        = 5

  # `ref` is a tag reference (`ghcr.io/acme/web:v1`, `nginx`, `redis:7`). Returns the
  # same image pinned — `docker.io/library/redis@sha256:…` — normalised to its full
  # name, because that is what will actually be pulled and a short name hides which
  # registry that was. Raises `Error` with a sentence a person can act on.
  def self.pin(ref)
    ref = ref.to_s.strip
    raise Error, "Type an image first — like ghcr.io/acme/web:v1." if ref.empty?
    # Already pinned. Not an error: it is the answer, and re-asking would be a chance
    # for the digest to differ from the one under discussion.
    return ref if ref.include?("@sha256:")

    host, repo, tag = parse(ref)
    "#{host}/#{repo}@#{resolve(host, repo, tag)}"
  end

  # Split a reference the way a container runtime does. The first segment is a registry
  # only if it looks like a host — a dot, a port, or `localhost` — which is why
  # `acme/web` is a Docker Hub repository and `acme.io/web` is not. A bare Hub name
  # lives under `library/`. Pure, so the awkward cases are cheap to pin down in tests.
  def self.parse(ref)
    name, tag = split_tag(ref)
    head, slash, rest = name.partition("/")

    if slash.present? && (head.include?(".") || head.include?(":") || head == "localhost")
      [ head, rest, tag ]
    else
      [ DEFAULT_HOST, name.include?("/") ? name : "library/#{name}", tag ]
    end
  end

  # A colon after the last slash is a tag; one before it is a registry's port.
  def self.split_tag(name)
    slash = name.rindex("/") || -1
    colon = name.rindex(":")
    colon && colon > slash ? [ name[0...colon], name[(colon + 1)..] ] : [ name, "latest" ]
  end

  # The network half, kept separate so everything above it is testable without one.
  def self.resolve(host, repo, tag)
    api = host == DEFAULT_HOST ? DOCKER_HUB_API : host
    res = manifest_head(api, repo, tag)
    # A public registry still hands out a token — anonymously — before it will answer.
    if res.is_a?(Net::HTTPUnauthorized) && (token = anonymous_token(res, repo))
      res = manifest_head(api, repo, tag, token: token)
    end

    case res
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise Error, "#{host} wants a credential for #{repo}. The console holds no registry " \
                   "logins by design — the box does, via `steward registry-login`. Paste the " \
                   "digest here instead."
    when Net::HTTPNotFound
      raise Error, "No tag #{tag} at #{host}/#{repo} — check the name and the tag."
    when Net::HTTPSuccess
      res[DIGEST_HEADER].presence ||
        raise(Error, "#{host} answered without a digest, so there is nothing to pin.")
    else
      raise Error, "#{host} answered HTTP #{res.code} for #{repo}:#{tag}."
    end
  end

  def self.manifest_head(api, repo, tag, token: nil)
    headers = { "Accept" => ACCEPT }
    headers["Authorization"] = "Bearer #{token}" if token
    get(URI.parse("#{scheme(api)}://#{api}/v2/#{repo}/manifests/#{tag}"), headers, head: true)
  end

  # The `WWW-Authenticate` challenge names where to ask and what to ask for. We only ever
  # ask for `pull` on the one repository being looked up, and we never send a credential,
  # so the worst this can obtain is what anyone could.
  def self.anonymous_token(res, repo)
    challenge = res["www-authenticate"].to_s
    return nil unless challenge.start_with?("Bearer ")

    parts = challenge.delete_prefix("Bearer ").scan(/(\w+)="([^"]*)"/).to_h
    realm = parts["realm"]
    return nil if realm.blank?

    uri = URI.parse(realm)
    uri.query = URI.encode_www_form(service: parts["service"], scope: "repository:#{repo}:pull")
    body = get(uri, {})
    return nil unless body.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(body.body) rescue nil
    parsed && (parsed["token"] || parsed["access_token"]).presence
  end

  # https everywhere except a loopback registry, which is how container tooling already
  # treats `localhost:5000` and is the only way to run one without a certificate.
  def self.scheme(api)
    api.start_with?("localhost", "127.0.0.1", "[::1]") ? "http" : "https"
  end

  def self.get(uri, headers, head: false)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      head ? http.head(uri.request_uri, headers) : http.get(uri.request_uri, headers)
    end
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise Error, "Couldn't reach #{uri.host}: #{e.class.name.demodulize}."
  end
end
