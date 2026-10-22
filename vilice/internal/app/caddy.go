package app

// The Caddyfile, rendered from every app's state and reloaded.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// --- Caddy ---

func refreshCaddy() error {
	apps, err := listApps()
	if err != nil {
		return err
	}
	// The render boundary, same as writeUnit: app state comes off disk here, and
	// loadApp deliberately doesn't validate (an app whose spec no longer passes should
	// fail loudly at its next deploy, not vanish from `status` and lose its route). So
	// the check happens on the way *into* the fragment. Refusing before the write means
	// the previous fragment stays — nothing changed — rather than quietly dropping an
	// app's route or writing config nobody declared.
	for _, a := range apps {
		if err := validateRenderable(a); err != nil {
			return fmt.Errorf("app %q has an invalid spec, so routing was left untouched: %w", a.Name, err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(caddyFragmentPath()), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(caddyFragmentPath(), []byte(renderCaddyfile(apps)), 0o644); err != nil {
		return err
	}
	// Reload via the admin socket (no root): adapt the base Caddyfile, which imports our
	// fragment, and push it to the running Caddy.
	return caddyReload()
}

// caddyReload applies the current config through Caddy's admin socket. It needs no root —
// the _vilice group may write to the socket — so the _vilice user can do it. The address
// is named rather than read from the config, so a box whose Caddyfile has lost the admin
// line fails the reload instead of quietly going back to localhost:2019.
func caddyReload() error {
	c := userExec("caddy", "reload", "--config", caddyfilePath(), "--adapter", "caddyfile",
		"--address", "unix/"+caddyAdminSocket)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

// renderCaddyfile is pure: one reverse-proxy site per app. An app's hostnames share
// one site address (space-separated, as Caddy expects). Each name is used as given —
// a bare domain gets Caddy's automatic HTTPS; an http:// prefix stays HTTP.
func renderCaddyfile(apps []appState) string {
	// Caddy rejects a truly empty config ("EOF"); a comment is a valid no-op, which
	// is what we want once the last app is removed.
	if len(apps) == 0 {
		return "# Managed by vilice. No apps deployed.\n"
	}
	var b strings.Builder
	for _, a := range apps {
		fmt.Fprintf(&b, "%s {\n\treverse_proxy 127.0.0.1:%d\n}\n\n", strings.Join(a.Hostnames, " "), a.livePort())
	}
	return b.String()
}
