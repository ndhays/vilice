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

# --- Vilice Console image (registry: ghcr.io to start; override IMAGE) ---
# NOTE: Boxcar is a local path gem, which a plain build context can't see. A
# deployable image needs Boxcar in-context (podman build --build-context, a git
# source, or vendor-at-build). See decisions/open/console-open-questions.md.
IMAGE ?= ghcr.io/agoraforge/vilice-console
TAG   ?= $(shell cat VERSION)

image:        ; podman build -t $(IMAGE):$(TAG) -t $(IMAGE):latest console
push:         ; podman push $(IMAGE):$(TAG) && podman push $(IMAGE):latest
