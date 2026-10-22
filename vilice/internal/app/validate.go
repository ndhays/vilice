package app

// What a spec must satisfy before it is stored or rendered. See
// decisions/rendered-config-is-a-boundary.md.

import (
	"vilice/internal/core"

	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// validateState is the full check, applied where a spec **enters** the box: a deploy
// (flags or stdin envelope) and a restore. It is validateRenderable plus the rules about
// what an app may *ask for* — currently where a bind mount may live.
//
// The split matters on upgrade. A policy rule checked on the way out would condemn an
// app that was already here and already working: tighten the bind-mount rule and a box
// with data at /data suddenly can't route anything. Checking policy on the way in is
// enough for the security property, because to exploit it you have to *introduce* a
// hostile volume, and the two doors above are the only ways to do that. An app already
// on the box was put there by the operator, not by an attacker.
// See decisions/rendered-config-is-a-boundary.md.
func validateState(st appState) error {
	if err := validateRenderable(st); err != nil {
		return err
	}
	for _, v := range st.Volumes {
		if err := validVolume(v); err != nil {
			return err
		}
	}
	for _, h := range st.Hostnames {
		if err := servableHostname(h); err != nil {
			return err
		}
	}
	return nil
}

// servableHostname refuses a hostname this box could route and never serve: a wildcard
// over HTTPS. A wildcard certificate is issued only by a DNS challenge, and the box's
// Caddy answers the HTTP and TLS ones. So the deploy would succeed, Caddy would retry
// for ever, and the operator would meet a TLS error with nothing pointing at why.
//
// Policy, so it is checked where a spec enters and not at the render boundary: a
// wildcard is a well-formed site address, and an app already here with one must keep
// rendering. An http:// wildcard needs no certificate and is left alone.
func servableHostname(h string) error {
	if strings.HasPrefix(h, "http://") || !strings.HasPrefix(strings.TrimPrefix(h, "https://"), "*.") {
		return nil
	}
	return fmt.Errorf("hostname %q is a wildcard, and this box cannot get a certificate for one: "+
		"that takes a DNS challenge, which Vilice does not do yet. Name each hostname instead, "+
		`like "app.example.com" and "www.example.com"`, h)
}

// validateRenderable is the subset that keeps a rendered file well-formed: nothing here
// may end its own line and start a directive nobody wrote. It is checked everywhere,
// including on state read back off disk, because it is about the *shape* of the file
// being written rather than about what the app is allowed to have.
func validateRenderable(st appState) error {
	switch {
	case st.Name == "":
		return fmt.Errorf("missing <app>")
	case !core.ValidAppName(st.Name):
		return fmt.Errorf("app name must be [A-Za-z0-9_-]")
	case st.Image == "":
		return fmt.Errorf("missing image")
	case core.HasControlChar(st.Image):
		return fmt.Errorf("image reference contains a control character")
	case !strings.Contains(st.Image, "@sha256:"):
		return fmt.Errorf("image must be digest-pinned (@sha256:…)")
	case len(st.Hostnames) == 0:
		return fmt.Errorf("missing hostname")
	case st.Port < 1024 || st.Port > 65535:
		return fmt.Errorf("port %d is out of range — use 1024–65535 (the container runs unprivileged and can't bind a port below 1024)", st.Port)
	case core.HasControlChar(st.Backup):
		return fmt.Errorf("backup hook contains a control character")
	}
	if err := validRelease(st.Release); err != nil {
		return err
	}
	if err := validAccessories(st); err != nil {
		return err
	}
	if err := validProcesses(st); err != nil {
		return err
	}
	if err := validDigestPin(st.Image); err != nil {
		return err
	}
	for _, h := range st.Hostnames {
		if err := validHostname(h); err != nil {
			return err
		}
	}
	// Only the part that affects the unit file's shape. Where the mount may *point* is
	// policy, checked by validateState at the doors.
	for _, v := range st.Volumes {
		if core.HasControlChar(v) {
			return fmt.Errorf("volume %q contains a control character", v)
		}
	}
	envSecret := map[string]bool{}
	for _, name := range st.Secrets {
		if !validEnvName(name) {
			return fmt.Errorf("invalid secret name %q", name)
		}
		envSecret[name] = true
	}
	for name, path := range st.SecretFiles {
		if !validEnvName(name) {
			return fmt.Errorf("invalid secret-file name %q", name)
		}
		if envSecret[name] {
			return fmt.Errorf("secret %q is declared as both an env secret and a file", name)
		}
		if !strings.HasPrefix(path, "/") {
			return fmt.Errorf("secret-file %q needs an absolute container path, got %q", name, path)
		}
		if core.HasControlChar(path) {
			return fmt.Errorf("secret-file %q path contains a control character", name)
		}
	}
	for k, v := range st.Env {
		if !validEnvName(k) {
			return fmt.Errorf("invalid env name %q", k)
		}
		// A newline in a value would end the Environment= line and start a directive
		// of the caller's choosing. Values needing one belong in the secret store,
		// which delivers them on stdin rather than through the unit file.
		if core.HasControlChar(v) {
			return fmt.Errorf("env %q has a control character in its value — use a secret for multi-line values", k)
		}
	}
	return nil
}

// validHostname accepts what a Caddy site address may be: an optional http:// or
// https:// scheme, an optional "*." wildcard, a hostname of letters, digits, dots and
// hyphens, and an optional :port.
//
// It is an allow-list because a block-list kept missing cases. Whitespace starts a
// *second* address on the same site (that is how several hostnames are written); a
// brace opens or closes a block; and a leading "#" comments out the site's opening
// line, leaving a dangling `reverse_proxy` that makes the whole fragment — every app's
// routing, not just this one's — fail to load. That last one a hand-written list of
// bad characters missed and the fuzzer found.
// See decisions/rendered-config-is-a-boundary.md.
func validHostname(h string) error {
	const shape = `hostname %q is not a site address — use "app.example.com", "http://app.example.com", or "host:port"`
	rest := h
	for _, scheme := range []string{"http://", "https://"} {
		if strings.HasPrefix(rest, scheme) {
			rest = strings.TrimPrefix(rest, scheme)
			break
		}
	}
	rest = strings.TrimPrefix(rest, "*.")
	if i := strings.LastIndexByte(rest, ':'); i >= 0 {
		port, err := strconv.Atoi(rest[i+1:])
		if err != nil || port < 1 || port > 65535 {
			return fmt.Errorf(shape, h)
		}
		rest = rest[:i]
	}
	if rest == "" {
		return fmt.Errorf(shape, h)
	}
	for _, r := range rest {
		ok := r == '.' || r == '-' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !ok {
			return fmt.Errorf(shape, h)
		}
	}
	return nil
}

// bindRoots is where a bind-mounted volume source may live. Named volumes are
// unrestricted (Podman owns that namespace and keeps them in the _vilice user's own
// storage); a *host path* is the one that can reach out of the app's world, so it is
// confined to a declared root. Without this an operate key could mount `/` — or just
// ~_vilice/.ssh — and write itself an ssh grant, stepping over the scope ladder.
// See decisions/rendered-config-is-a-boundary.md.
func bindRoots() []string {
	if p := os.Getenv("VILICE_BIND_ROOTS"); p != "" {
		return filepath.SplitList(p)
	}
	return []string{"/srv"}
}

// validVolume checks one `<src>:<dst>[:opts]` volume spec.
func validVolume(v string) error {
	if core.HasControlChar(v) {
		return fmt.Errorf("volume %q contains a control character", v)
	}
	src := volumeSource(v)
	if src == "" {
		return fmt.Errorf("volume %q has no source", v)
	}
	if !strings.HasPrefix(src, "/") {
		if !core.ValidAppName(src) {
			return fmt.Errorf("named volume %q must be [A-Za-z0-9_-]", src)
		}
		return nil
	}
	clean := filepath.Clean(src)
	for _, root := range bindRoots() {
		if clean == root || strings.HasPrefix(clean, strings.TrimSuffix(root, "/")+"/") {
			return nil
		}
	}
	return fmt.Errorf("bind mount %q is outside %s — put app data under %s, or use a named volume",
		src, strings.Join(bindRoots(), " or "), bindRoots()[0])
}

// validEnvName accepts shell/env var names: [A-Za-z_][A-Za-z0-9_]*.
func validEnvName(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		switch {
		case r >= 'A' && r <= 'Z', r >= 'a' && r <= 'z', r == '_':
		case r >= '0' && r <= '9' && i > 0:
		default:
			return false
		}
	}
	return true
}
