# Top-level orchestration. Most work lives in the subprojects; this delegates.
.PHONY: build build-linux test check audit audit-box sign release site-build image push clean

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

# --- Vilice Console image (registry: ghcr.io to start; override IMAGE) ---
# NOTE: Boxcar is a local path gem, which a plain build context can't see. A
# deployable image needs Boxcar in-context (podman build --build-context, a git
# source, or vendor-at-build). See decisions/open/console-open-questions.md.
IMAGE ?= ghcr.io/agoraforge/vilice-console
TAG   ?= $(shell cat VERSION)

image:        ; podman build -t $(IMAGE):$(TAG) -t $(IMAGE):latest console
push:         ; podman push $(IMAGE):$(TAG) && podman push $(IMAGE):latest
