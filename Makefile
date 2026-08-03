# Top-level orchestration. Most work lives in the subprojects; this delegates.
.PHONY: build build-linux test audit audit-box sign release site-build image push clean

build:        ; $(MAKE) -C steward build
build-linux:  ; $(MAKE) -C steward build-linux
test:         ; $(MAKE) -C steward test
audit:        ; $(MAKE) -C steward audit
# Box-posture audit against a live box (ssh-audit + nmap + Lynis). Needs HOST.
# e.g. make audit-box HOST=devbox
audit-box:    ; ./audit/run.sh $(HOST)
sign:         ; $(MAKE) -C steward sign
release:      ; $(MAKE) -C steward release
site-build:   ; cd site && npm run build
clean:        ; $(MAKE) -C steward clean

# --- Steward Console image (registry: ghcr.io to start; override IMAGE) ---
# NOTE: Boxcar is a local path gem, which a plain build context can't see. A
# deployable image needs Boxcar in-context (podman build --build-context, a git
# source, or vendor-at-build). See decisions/open/console-open-questions.md.
IMAGE ?= ghcr.io/agoraforge/steward-console
TAG   ?= $(shell cat VERSION)

image:        ; podman build -t $(IMAGE):$(TAG) -t $(IMAGE):latest console
push:         ; podman push $(IMAGE):$(TAG) && podman push $(IMAGE):latest
