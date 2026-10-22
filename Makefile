# Top-level orchestration. Most work lives in the subprojects; this delegates.
.PHONY: build build-linux test check audit audit-box sign release site-build publish publish-check image push clean

build:        ; $(MAKE) -C vilice build
build-linux:  ; $(MAKE) -C vilice build-linux
test:         ; $(MAKE) -C vilice test
# Formatted, vetted, tested — what CI runs (.github/workflows/ci.yml).
check:        ; $(MAKE) -C vilice check
audit:        ; $(MAKE) -C vilice audit
# Box-posture audit against a live box (ssh-audit + nmap + Lynis). Needs HOST.
# e.g. make audit-box HOST=devbox
audit-box:    ; ./audit/run.sh $(HOST)
sign:         ; $(MAKE) -C vilice sign
release:      ; $(MAKE) -C vilice release
site-build:   ; cd site && npm run build
clean:        ; $(MAKE) -C vilice clean

# --- Publishing the two hosts -------------------------------------------------------
# One deliberate command, run from a machine that holds the release — never a push. It
# is the gate in decisions/the-name-is-vilice.md, made a script:
#   1. the key on Codeberg is the key in this repo, or nothing is published;
#   2. get.vilice.org goes up first, and must serve this version's release;
#   3. only then vilice.org, whose install line names that version.
# Needs Cloudflare access: `npx wrangler login`, or CLOUDFLARE_API_TOKEN in the env.
WRANGLER   ?= npx --yes wrangler@4
RELEASE    := $(shell cat VERSION)
PUBKEY_URL ?= https://codeberg.org/vilice/vilice/raw/branch/main/release-key.pub
GET_HOST   ?= https://get.vilice.org

# Build both, and check everything `publish` checks before it uploads — without
# uploading. Safe to run any time.
publish-check: site-build
	@test -f site/dist-get/releases/vilice/$(RELEASE)/vilice-linux-amd64.tar.gz.sig || { \
	  echo "site/dist-get has no release for v$(RELEASE) — run 'make release' first"; exit 1; }
	@test "$$(curl -fsSL $(PUBKEY_URL) | tr -d '\n')" = "$$(tr -d '\n' < vilice/release-key.pub)" || { \
	  echo "the key at $(PUBKEY_URL) is not vilice/release-key.pub —"; \
	  echo "  every install would fail its check. Nothing published."; exit 1; }
	@echo "✓ v$(RELEASE) is built, and the Codeberg key matches"
	cd site && $(WRANGLER) deploy --config wrangler.get.jsonc --dry-run
	cd site && $(WRANGLER) deploy --config wrangler.site.jsonc --dry-run

publish: publish-check
	cd site && $(WRANGLER) deploy --config wrangler.get.jsonc
	@curl -fsS --retry 6 --retry-delay 5 --retry-all-errors -o /dev/null \
	  $(GET_HOST)/releases/vilice/$(RELEASE)/vilice-linux-amd64.tar.gz.sig || { \
	  echo "$(GET_HOST) does not serve v$(RELEASE) — the docs were NOT published."; exit 1; }
	@echo "✓ $(GET_HOST) serves v$(RELEASE)"
	cd site && $(WRANGLER) deploy --config wrangler.site.jsonc
	@echo "✓ published v$(RELEASE): $(GET_HOST), then https://vilice.org"

# --- Vilice Console image ----------------------------------------------------------
# Built from commits only, for the boxes' architecture, and tagged with the commit — so
# an image always names the code in it. Boxcar (a path gem in a sibling checkout) and
# VERSION (the repo root's) are outside console/, so they arrive as named build
# contexts. Vilice deploys by digest, so there is no `latest`: `push` prints the digest
# to deploy. Override IMAGE for your registry, e.g. IMAGE=zot.example.com/vilice-console.
IMAGE    ?= ghcr.io/agoraforge/vilice-console
PLATFORM ?= linux/amd64
BOXCAR   ?= ../boxcar-rails
REV       = $(shell git rev-parse --short HEAD)

image:
	@test -z "$$(git status --porcelain)" || { \
	  echo "uncommitted changes — an image is built from a commit:"; git status --short; exit 1; }
	@test -d "$(BOXCAR)" || { echo "Boxcar not found at $(BOXCAR) (set BOXCAR=…)"; exit 1; }
	@test -z "$$(git -C $(BOXCAR) status --porcelain)" || { \
	  echo "uncommitted changes in $(BOXCAR) — Boxcar goes in as a commit too"; exit 1; }
	podman build --platform $(PLATFORM) \
	  --build-context boxcar=$(BOXCAR) --build-context repo=. \
	  --label org.opencontainers.image.revision=$$(git rev-parse HEAD) \
	  --label org.opencontainers.image.version=$$(cat VERSION) \
	  --label boxcar.revision=$$(git -C $(BOXCAR) rev-parse HEAD) \
	  -t $(IMAGE):$(REV) console

push:
	@d=$$(mktemp); podman push --digestfile $$d $(IMAGE):$(REV) && \
	  echo "pushed. Deploy it as: $(IMAGE)@$$(cat $$d)"; rm -f $$d
