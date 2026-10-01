package app

// Accessories: the database or cache an app needs, on the same box, reachable by that
// app and by nothing else.
//
// **Subordinate by construction**, and that is the whole design. An accessory has no
// hostname and is never routed; it lives on a network only its own app joins; it is
// created with that app and destroyed with it. It is not a second kind of app — it is
// part of one app's declaration, inside the same spec digest.
//
// Why not "an accessory is just another app": an app is a thing Caddy routes to. It
// must have a hostname (`validateState`) and it is health-checked over HTTP
// (`waitHealthy`), neither of which a Postgres has. Making apps mean two things — routed
// and not — is a larger and worse change than adding a scoped, subordinate noun.
//
// **The network is the isolation.** One network per app, so declaring that `web` needs a
// database gets `web → db` and never `anything → db`. The alternative on a single box is
// the shared host loopback, which would grant both at once — connectivity and isolation
// are one decision here, and this is it. See decisions/accessories-belong-to-one-app.md.
//
// **No blue/green.** An accessory holds data on a disk; two containers over one data
// directory is not a deploy strategy, it is corruption. So an accessory is a single
// container that persists *across* the app's color flips, and the app's colors come and
// go around it. That is the same rule `replicable?` already applies one layer up: a
// thing that keeps data is single.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"vilice/internal/core"
)

// Accessory is one supporting container. Deliberately smaller than an app: no hostname,
// no health path, no count, no colors — the fields that only mean something for a thing
// the world reaches are absent rather than ignored.
type Accessory struct {
	// Name is also the **DNS name the app uses** (`db:5432`), via a network alias.
	Name    string            `json:"name"`
	Image   string            `json:"image"` // digest-pinned, like the app's
	Env     map[string]string `json:"env,omitempty"`
	Secrets []string          `json:"secrets,omitempty"` // names; values ride the same envelope
	Volumes []string          `json:"volumes,omitempty"`
}

// accessoryNetwork is the per-app network. Named for the app, because that is exactly
// its scope: nothing else ever joins it.
func accessoryNetwork(app string) string { return "vilice-" + app }

// accessoryContainer is the container's real name. The app addresses it by the short
// alias instead, so a spec never has to know this.
func accessoryContainer(app, name string) string { return app + "-" + name }

func accessoryUnitFile(app, name string) string { return accessoryContainer(app, name) + ".container" }
func accessoryService(app, name string) string  { return accessoryContainer(app, name) + ".service" }

// validAccessories checks the declaration. The rules that matter are the ones that would
// otherwise fail confusingly much later, or collide with something already on the box.
func validAccessories(st appState) error {
	seen := map[string]bool{}
	for _, a := range st.Accessories {
		switch {
		case !core.ValidAppName(a.Name):
			return fmt.Errorf("accessory name %q must be [A-Za-z0-9_-]", a.Name)
		// `a` and `b` are the app's own color suffixes, so an accessory by either name
		// would render a unit file that collides with a color's. Refuse it here rather
		// than let one clobber the other on disk.
		case a.Name == "a" || a.Name == "b":
			return fmt.Errorf("accessory may not be named %q — that is a deploy color", a.Name)
		case a.Name == st.Name:
			return fmt.Errorf("accessory %q may not share its app's name", a.Name)
		case seen[a.Name]:
			return fmt.Errorf("accessory %q is declared twice", a.Name)
		case a.Image == "":
			return fmt.Errorf("accessory %q has no image", a.Name)
		case core.HasControlChar(a.Image):
			return fmt.Errorf("accessory %q: image reference contains a control character", a.Name)
		// The same pin the app's own image needs, for the same reason: a tag means
		// something different tomorrow, and "which database was running" has to have an
		// answer (decisions/a-tag-is-not-a-release.md). Both halves are needed — the
		// presence of the marker and the shape of what follows it — because
		// `validDigestPin` checks only the second and says nothing about `postgres:16`.
		case !strings.Contains(a.Image, "@sha256:"):
			return fmt.Errorf("accessory %q: image must be digest-pinned (@sha256:…)", a.Name)
		}
		if err := validDigestPin(a.Image); err != nil {
			return fmt.Errorf("accessory %q: %w", a.Name, err)
		}
		for _, v := range a.Volumes {
			if err := validVolume(v); err != nil {
				return fmt.Errorf("accessory %q: %w", a.Name, err)
			}
		}
		for _, s := range a.Secrets {
			if !validEnvName(s) {
				return fmt.Errorf("accessory %q: invalid secret name %q", a.Name, s)
			}
		}
		seen[a.Name] = true
	}
	return nil
}

// accessorySecretNames returns the app-scoped secret names an accessory declares, so the
// one envelope carries values for the app and its accessories alike. Namespaced by
// container, so `db`'s POSTGRES_PASSWORD and the app's never collide in the store.
func accessorySecretRef(app, accessory, name string) string {
	return accessoryContainer(app, accessory) + "__" + name
}

// renderAccessoryUnit is pure: the rootless `.container` file for one accessory. It is
// the app's unit minus everything an unrouted container has no use for — no published
// port (nothing outside the network may reach it), no color — plus the network and the
// alias its app resolves it by.
func renderAccessoryUnit(app string, a Accessory) string {
	var b strings.Builder
	b.WriteString("# Managed by vilice. Generated from app-state — do not edit.\n")
	b.WriteString("[Unit]\n")
	fmt.Fprintf(&b, "Description=Vilice accessory %s for %s\n\n", a.Name, app)

	b.WriteString("[Container]\n")
	fmt.Fprintf(&b, "Image=%s\n", a.Image)
	fmt.Fprintf(&b, "ContainerName=%s\n", accessoryContainer(app, a.Name))
	// **No PublishPort.** An accessory is reachable on the app's network and nowhere
	// else — not from another app, not from the host, not from outside. That absence is
	// the isolation, so it is stated here rather than left as an omission.
	fmt.Fprintf(&b, "Network=%s\n", accessoryNetwork(app))
	fmt.Fprintf(&b, "NetworkAlias=%s\n", a.Name)
	for _, k := range sortedKeys(a.Env) {
		fmt.Fprintf(&b, "Environment=%s\n", quoteEnv(k, a.Env[k]))
	}
	for _, name := range a.Secrets {
		fmt.Fprintf(&b, "Secret=%s,type=env,target=%s\n", accessorySecretRef(app, a.Name, name), name)
	}
	for _, v := range a.Volumes {
		fmt.Fprintf(&b, "Volume=%s\n", v)
	}
	// The same ceiling the app's unit carries — an accessory is not a chance to run with
	// more than the app has (see renderQuadletUnit).
	b.WriteString("NoNewPrivileges=true\n")
	b.WriteString("DropCapability=CAP_NET_BIND_SERVICE CAP_SETFCAP CAP_SETPCAP CAP_SYS_CHROOT\n")

	b.WriteString("\n[Service]\n")
	fmt.Fprintf(&b, "TimeoutStopSec=%d\n", drainTimeoutSecs)
	b.WriteString("Restart=on-failure\n")
	// A database is worth more than the app in front of it: under memory pressure the
	// kernel should take the app first, and the app's own unit already volunteers.
	b.WriteString("OOMScoreAdjust=0\n")
	b.WriteString("\n[Install]\nWantedBy=default.target\n")
	return b.String()
}

// ensureAccessories brings the app's network and every declared accessory up, and takes
// away any accessory the spec no longer declares. Idempotent: an accessory whose unit is
// already exactly this is left running, because restarting a database nobody asked to
// change is an outage nobody asked for.
func ensureAccessories(st appState) error {
	if len(st.Accessories) == 0 {
		return pruneAccessories(st, nil)
	}
	if err := ensureNetwork(accessoryNetwork(st.Name)); err != nil {
		return err
	}

	changed := false
	keep := map[string]bool{}
	for _, a := range st.Accessories {
		keep[a.Name] = true
		wrote, err := writeAccessoryUnit(st.Name, a)
		if err != nil {
			return err
		}
		changed = changed || wrote
	}
	if err := pruneAccessories(st, keep); err != nil {
		return err
	}
	if changed {
		if err := daemonReload(); err != nil {
			return fmt.Errorf("daemon-reload: %w", err)
		}
	}
	for _, a := range st.Accessories {
		// `restart` on a unit that is down starts it, and on one that is up applies the
		// file we just wrote. Only reached when something actually changed.
		verb := "start"
		if changed {
			verb = "restart"
		}
		if err := userctl(verb, accessoryService(st.Name, a.Name)); err != nil {
			return fmt.Errorf("%s %s: %w", verb, accessoryContainer(st.Name, a.Name), err)
		}
	}
	return nil
}

// writeAccessoryUnit writes the unit and reports whether it differs from what was there.
// The comparison is what keeps a redeploy from bouncing an unchanged database.
func writeAccessoryUnit(app string, a Accessory) (changed bool, err error) {
	dir, err := quadletDir()
	if err != nil {
		return false, err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}
	path := filepath.Join(dir, accessoryUnitFile(app, a.Name))
	next := renderAccessoryUnit(app, a)
	if prev, readErr := os.ReadFile(path); readErr == nil && string(prev) == next { // #nosec G304 -- vilice's own unit dir
		return false, nil
	}
	return true, os.WriteFile(path, []byte(next), 0o644)
}

// pruneAccessories removes units for accessories the spec no longer declares. `keep` nil
// means keep none — the app declares no accessories at all, or is being removed.
//
// **It stops the container and deletes the unit; it never removes a volume.** Undeclaring
// a database must not be how its data disappears. That is the same rule the console's
// intention layer follows: withdrawing a statement of desire is not a destructive act.
func pruneAccessories(st appState, keep map[string]bool) error {
	dir, err := quadletDir()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	prefix := st.Name + "-"
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, prefix) || !strings.HasSuffix(name, ".container") {
			continue
		}
		short := strings.TrimSuffix(strings.TrimPrefix(name, prefix), ".container")
		// A color's unit is not an accessory's, and neither is another app's whose name
		// happens to start the same way — `keep` only ever names this app's accessories.
		if short == "a" || short == "b" || keep[short] {
			continue
		}
		if !core.ValidAppName(short) {
			continue
		}
		_ = userctl("stop", accessoryService(st.Name, short))
		_ = userctl("disable", accessoryService(st.Name, short))
		if err := os.Remove(filepath.Join(dir, name)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

// teardownAccessories is `remove`'s half: every accessory and the network with them.
// Volumes still survive — `remove` has its own opt-in for those.
func teardownAccessories(app string) {
	st := appState{Name: app}
	_ = pruneAccessories(st, nil)
	_ = daemonReload()
	_ = userExec("podman", "network", "rm", "-f", accessoryNetwork(app)).Run()
}

// ensureNetwork creates the app's network if it is not already there. `network create`
// on an existing network is an error rather than a no-op, so existence is checked first.
func ensureNetwork(name string) error {
	if err := userExec("podman", "network", "exists", name).Run(); err == nil {
		return nil
	}
	if out, err := podmanOutput("network", "create", name); err != nil {
		return fmt.Errorf("create network %s: %s", name, strings.TrimSpace(out))
	}
	return nil
}
