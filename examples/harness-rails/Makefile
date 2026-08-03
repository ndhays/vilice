# Build and publish the harness image. The devbox is amd64 and this dev machine may be
# arm64, so `push` builds a multi-arch manifest (needs qemu/binfmt for the foreign arch).
#
#   make build              # native-arch image, for a quick local check
#   make push               # multi-arch (amd64 + arm64) manifest → GHCR
IMAGE ?= ghcr.io/agoraforge/harness-rails
TAG   ?= latest
PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: build push

build:
	podman build -t $(IMAGE):$(TAG) -f Containerfile .

push:
	podman manifest rm $(IMAGE):$(TAG) 2>/dev/null || true
	podman build --platform $(PLATFORMS) --manifest $(IMAGE):$(TAG) -f Containerfile .
	podman manifest push --all $(IMAGE):$(TAG) docker://$(IMAGE):$(TAG)
