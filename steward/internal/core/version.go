package core

// Version is set at build time from the VERSION file via
//
//	-ldflags "-X steward/internal/core.Version=$(cat VERSION)"
//
// (see the Makefile). VERSION is the source of truth; the docs site reads it too.
// A plain `go build`/`go run` without ldflags reports "dev".
var Version = "dev"
