package app

// `deploy` and the app lifecycle (operate scope). Wide, not deep: a state machine
// over borrowed muscle — Podman runs the container, Caddy routes to it. Failures are
// loud and recoverable; a failed deploy leaves the running app untouched. v1 cutover
// is non-gapless. See blueprint/steward/deploy.md.

import (
	"steward/internal/core"

	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// appState is what we know about a deployed app. Persisted so we can rebuild the
// Caddy config, roll back, and drive the lifecycle. One JSON file per app.
// It holds the declared desired state (env, secret *names*, volumes) plus the
// runtime facts. Secret *values* never live here — only in the secret store.
type appState struct {
	Name      string            `json:"name"`
	Image     string            `json:"image"`
	Hostnames []string          `json:"hostnames"`         // one or more; Caddy routes all of them to the app
	Port      int               `json:"port"`              // the port the app listens on inside the container
	Health    string            `json:"health"`            // health path, e.g. "/"
	Env       map[string]string `json:"env,omitempty"`     // config — recorded
	Secrets   []string          `json:"secrets,omitempty"` // secret names only, never values
	// SecretFiles maps a secret name to a container path; its value (on stdin, never
	// recorded) is mounted there as a file rather than injected as an env var.
	SecretFiles map[string]string `json:"secret_files,omitempty"`
	Volumes     []string          `json:"volumes,omitempty"`
	// Release runs once from the new image before the new color starts — migrations are
	// the case it exists for. **argv, not a shell string**, so a multi-step release lives
	// in a script inside the image where the digest covers it. See release.go.
	Release []string `json:"release,omitempty"`
	// Accessories are the containers this app needs and nothing else may reach — a
	// database, a cache. Subordinate: no hostname, never routed, on a network only this
	// app joins, created and destroyed with it. See accessory.go.
	Accessories []Accessory `json:"accessories,omitempty"`
	// Processes are the app's other containers — a worker, a clock. Same image, same env,
	// same secrets, same volumes, a different command; they flip with the app's colours
	// so web and worker can never drift onto different digests. See process.go.
	Processes []Process `json:"processes,omitempty"`
	Backup    string    `json:"backup,omitempty"` // in-container pre-snapshot consistency hook (see backup.go)
	Digest    string    `json:"digest,omitempty"` // sha256 of the canonical spec (sans secret values)
	HostPort  int       `json:"host_port"`        // legacy single-container port (pre-Quadlet); see livePort
	PrevImage string    `json:"prev_image"`       // last-good before this one, for rollback

	// Blue/green (Quadlet): the live color Caddy points at, and each color's fixed
	// loopback port. A deploy writes the inactive color, then flips ActiveColor.
	ActiveColor string         `json:"active_color,omitempty"` // "a" | "b"
	Ports       map[string]int `json:"ports,omitempty"`        // color -> published loopback port
}

// livePort is the loopback port Caddy should target: the active color's published
// port. Falls back to the legacy HostPort during the pre-Quadlet transition.
func (st appState) livePort() int {
	if st.ActiveColor != "" {
		if p, ok := st.Ports[st.ActiveColor]; ok {
			return p
		}
	}
	return st.HostPort
}

// appSpec is the declared desired state, sent as JSON on stdin. Secret *names*
// live here; secret *values* never do (they ride deployEnvelope.SecretValues).
type appSpec struct {
	Image       string            `json:"image"`
	Hostnames   []string          `json:"hostnames"`
	Port        int               `json:"port"`
	Health      string            `json:"health"`
	Env         map[string]string `json:"env,omitempty"`
	Secrets     []string          `json:"secrets,omitempty"`
	SecretFiles map[string]string `json:"secret_files,omitempty"`
	Volumes     []string          `json:"volumes,omitempty"`
	// Release is an optional argv run once from the new image before the new color
	// starts — migrations are the case it exists for. Declared here rather than passed
	// as a flag, so the same digest always runs the same step. See release.go.
	Release []string `json:"release,omitempty"`
	// Accessories the app needs on the same box — a database, a cache. Reachable by this
	// app alone, over a network only it joins. See accessory.go.
	Accessories []Accessory `json:"accessories,omitempty"`
	// Processes the app runs besides the web one — a worker, a clock. Argv only; they
	// inherit everything else from the app, which is what keeps them from drifting.
	Processes []Process `json:"processes,omitempty"`
	// Backup is an optional command run inside the container before a snapshot, so a
	// stateful app makes itself consistent (e.g. pg_dump into a declared volume). Keeps
	// Steward database-agnostic — the app owns its own consistency. See backup.go.
	Backup string `json:"backup,omitempty"`
}

// deployEnvelope is one sweep: the full spec plus the secret values it needs. The
// spec is recorded (by digest, sans values); secret_values are bound and never recorded.
type deployEnvelope struct {
	App          appSpec           `json:"app"`
	SecretValues map[string]string `json:"secret_values,omitempty"`
}

func appsDir() string {
	if p := os.Getenv("STEWARD_APPS_DIR"); p != "" {
		return p
	}
	return "/var/lib/steward/apps"
}

// caddyfilePath is the base config the system Caddy loads (root-owned); it imports the
// steward-owned fragment. caddyFragmentPath is the file Steward actually writes — its
// app routes, under /etc/caddy/steward/ so the caddy user can still read them.
func caddyfilePath() string {
	if p := os.Getenv("STEWARD_CADDYFILE"); p != "" {
		return p
	}
	return "/etc/caddy/Caddyfile"
}

func caddyFragmentPath() string {
	if p := os.Getenv("STEWARD_CADDY_FRAGMENT"); p != "" {
		return p
	}
	return "/etc/caddy/steward/apps.caddy"
}

// --- deploy ---

// deploy is a declarative upsert: it takes the app's full desired state and
// converges the box to it. The spec arrives as a JSON envelope on stdin (so secret
// values never touch the recorded command line); a flag form is kept for the simple,
// no-secret path. First deploy and Nth are the same call.
func deployCmd(args []string) core.Result {
	flags, pos := core.ParseArgs(args)
	name := firstPos(pos)
	if name == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}

	// Source the desired state: flags (simple path) or a stdin envelope (full path).
	var env deployEnvelope
	if flags["image"] != "" {
		env = envelopeFromFlags(flags)
	} else {
		data, err := readStdinSpec(os.Stdin)
		if err != nil {
			return core.Result{Code: "bad_args", Message: err.Error()}
		}
		if env, err = parseEnvelope(data); err != nil {
			return core.Result{Code: "bad_args", Message: err.Error()}
		}
	}

	// A balancer has no container runtime, on purpose. Say that, rather than letting the
	// operator meet "podman: not found" and guess why.
	if core.Role() == core.RoleBalancer {
		return core.Result{Code: "wrong_role",
			Message: "this box was prepared as a balancer — it fronts other boxes and runs no apps"}
	}

	st, err := stateFromSpec(name, env.App)
	if err != nil {
		return core.Result{Code: "bad_args", Message: err.Error()}
	}

	// One act on an app at a time. Taken *before* the record: a refusal here means
	// nothing was attempted, so nothing is written (lock.go).
	return resultOrErr(withAppLock(st.Name, func() error {
		return deployLocked(&st, env)
	}), "deploy_failed", fmt.Sprintf("deployed %q (%s) → %s",
		st.Name, shortDigest(st.Image), strings.Join(st.Hostnames, ", ")))
}

// deployLocked is `deploy` with the app's lock already held.
func deployLocked(st *appState, env deployEnvelope) error {
	// Record the resolved spec — by digest — *before* acting. The digest commits to
	// the exact spec (verifiable against app-state); secret values are never recorded.
	if err := core.Record(core.ActorName(), string(core.ScopeOperate), "deploy-spec", []string{st.Name, st.Digest}); err != nil {
		return &codedError{code: "record_failed", retryable: true, msg: err.Error()}
	}
	// Materialize declared secrets into the store (self-contained: values arrive now).
	if err := putSecrets(*st, env.SecretValues); err != nil {
		return &codedError{code: "secret_failed", retryable: true, msg: err.Error()}
	}
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		return &codedError{code: "io_error", msg: err.Error()}
	}
	return runDeploy(st)
}

// resultOrErr turns the error side of a locked act into a Result, or reports success.
func resultOrErr(err error, code, ok string) core.Result {
	if err != nil {
		return resultFromErr(err, code)
	}
	return core.OK(ok)
}

// parseDeployArgs builds a validated appState from flags (the simple, no-secret path).
func parseDeployArgs(args []string) (appState, error) {
	flags, pos := core.ParseArgs(args)
	return stateFromSpec(firstPos(pos), envelopeFromFlags(flags).App)
}

func envelopeFromFlags(flags map[string]string) deployEnvelope {
	app := appSpec{
		Image:  flags["image"],
		Health: flags["health"],
		Port:   atoiDefault(flags["port"], 8080),
	}
	if h := flags["hostname"]; h != "" {
		app.Hostnames = []string{h}
	}
	return deployEnvelope{App: app}
}

// parseEnvelope is pure: the JSON desired-state envelope from stdin.
func parseEnvelope(data []byte) (deployEnvelope, error) {
	var env deployEnvelope
	if err := json.Unmarshal(data, &env); err != nil {
		return deployEnvelope{}, fmt.Errorf("the deploy spec on stdin isn't valid JSON — check for a missing or trailing comma (%w)", err)
	}
	return env, nil
}

// readStdinSpec reads the envelope from stdin. It refuses a terminal (no spec piped)
// rather than block. Steward Console always pipes the envelope on the scoped-SSH call.
func readStdinSpec(f *os.File) ([]byte, error) {
	if info, err := f.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		return nil, fmt.Errorf("no --image flag and no spec on stdin")
	}
	return io.ReadAll(f)
}

// stateFromSpec validates the spec, applies defaults, and stamps the config digest.
func stateFromSpec(name string, s appSpec) (appState, error) {
	st := appState{
		Name: name, Image: s.Image, Hostnames: s.Hostnames,
		Port: s.Port, Health: s.Health,
		Env: s.Env, Secrets: s.Secrets, SecretFiles: s.SecretFiles, Volumes: s.Volumes,
		Release: s.Release, Accessories: s.Accessories, Processes: s.Processes,
		Backup: s.Backup,
	}
	if st.Port == 0 {
		st.Port = 8080
	}
	if st.Health == "" {
		st.Health = "/"
	}
	if err := validateState(st); err != nil {
		return appState{}, err
	}
	st.Digest = appDigest(st)
	return st, nil
}

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
	return nil
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
	const shape = `hostname %q is not a site address — use "app.example.com", "http://app.example.com", "*.example.com", or "host:port"`
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
// unrestricted (Podman owns that namespace and keeps them in the steward user's own
// storage); a *host path* is the one that can reach out of the app's world, so it is
// confined to a declared root. Without this an operate key could mount `/` — or just
// ~steward/.ssh — and write itself an ssh grant, stepping over the scope ladder.
// See decisions/rendered-config-is-a-boundary.md.
func bindRoots() []string {
	if p := os.Getenv("STEWARD_BIND_ROOTS"); p != "" {
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

// appDigest is the content address of the declared config: sha256 over the spec
// fields (secret names, never values), order-independent. Runtime fields (HostPort,
// PrevImage) and the app name are excluded — it identifies the *config*, not the run.
func appDigest(st appState) string {
	host := append([]string(nil), st.Hostnames...)
	sec := append([]string(nil), st.Secrets...)
	vol := append([]string(nil), st.Volumes...)
	sort.Strings(host)
	sort.Strings(sec)
	sort.Strings(vol)
	canonical := struct {
		Image       string            `json:"image"`
		Hostnames   []string          `json:"hostnames"`
		Port        int               `json:"port"`
		Health      string            `json:"health"`
		Env         map[string]string `json:"env"`
		Secrets     []string          `json:"secrets"`
		SecretFiles map[string]string `json:"secret_files"`
		Volumes     []string          `json:"volumes"`
		// Release is part of what the spec *is*: changing the command changes the
		// deploy, and the release container is named after this digest, so leaving it
		// out would let two different commands share one identity.
		Release []string `json:"release"`
		// An accessory's image and env are part of what this app *is*: changing the
		// database's version is a change to the deploy, not a detail beside it.
		Accessories []Accessory `json:"accessories"`
		// A process is part of what the app *is*, so changing a worker's command is a
		// change to the deploy — and the digest has to say so.
		Processes []Process `json:"processes"`
		Backup    string    `json:"backup"`
	}{st.Image, host, st.Port, st.Health, st.Env, sec, st.SecretFiles, vol, st.Release,
		st.Accessories, st.Processes, st.Backup}
	b, _ := json.Marshal(canonical) // map keys marshal sorted → deterministic
	sum := sha256.Sum256(b)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// secretRef namespaces a secret to its app (Podman secret names are global).
func secretRef(app, name string) string { return app + "__" + name }

func sortedKeys(m map[string]string) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

// declaredSecretNames is every secret an app declares — env (Secrets) and file
// (SecretFiles) alike. Both share one Podman store under secretRef, so storing and
// removing must cover the same set; routing remove through this helper keeps a file
// secret from orphaning in the store when its app is removed.
func declaredSecretNames(st appState) []string {
	names := make([]string, 0, len(st.Secrets)+len(st.SecretFiles))
	names = append(names, st.Secrets...)
	for n := range st.SecretFiles {
		names = append(names, n)
	}
	// An accessory's secrets ride the same envelope — one sweep carries everything this
	// app needs, the database password included. They are namespaced *in the store* by
	// the accessory's container (accessorySecretRef) but declared by their plain name
	// here, because that is the name the value arrives under.
	for _, a := range st.Accessories {
		names = append(names, a.Secrets...)
	}
	return names
}

// putSecrets stores each declared secret's value in the Podman secret store. Env
// secrets and file secrets share one store and one delivery (values arrive with the
// deploy, never recorded); only how the unit consumes them differs (env vs mount). An
// undeclared value, or a declared secret with no value, is an error.
func putSecrets(st appState, values map[string]string) error {
	declared := map[string]bool{}
	for _, n := range declaredSecretNames(st) {
		declared[n] = true
	}
	for name := range values {
		if !declared[name] {
			return fmt.Errorf("secret_values has %q, not declared in app.secrets or app.secret_files", name)
		}
	}
	// Where each declared name is stored. An accessory's secret lands under its own
	// container's namespace, so the app's POSTGRES_PASSWORD and the database's cannot
	// collide in a store whose names are global.
	ref := map[string]string{}
	for _, n := range st.Secrets {
		ref[n] = secretRef(st.Name, n)
	}
	for n := range st.SecretFiles {
		ref[n] = secretRef(st.Name, n)
	}
	for _, a := range st.Accessories {
		for _, n := range a.Secrets {
			ref[n] = accessorySecretRef(st.Name, a.Name, n)
		}
	}
	for name := range declared {
		val, ok := values[name]
		if !ok {
			return fmt.Errorf("no value provided for declared secret %q", name)
		}
		if err := putSecret(ref[name], val); err != nil {
			return fmt.Errorf("store secret %q: %w", name, err)
		}
	}
	return nil
}

// putSecret writes one value into the Podman secret store via stdin (never argv).
// rm-then-create makes it rotation-safe across Podman versions.
func putSecret(ref, value string) error {
	_ = userExec("podman", "secret", "rm", ref).Run() // ignore "no such secret"
	c := userExec("podman", "secret", "create", ref, "-")
	c.Stdin = strings.NewReader(value)
	c.Stderr = os.Stderr
	return c.Run()
}

// runDeploy is the blue/green Quadlet pipeline. The new image goes to the *inactive*
// color on a fresh port, alongside the live one; only after it's healthy and Caddy has
// flipped do we retire the old color. A failure tears down the new color and leaves the
// running app untouched — "nothing changed".
func runDeploy(st *appState) error {
	old, hadOld := loadApp(st.Name)
	target := otherColor(old.ActiveColor)

	// Fixed loopback port for the target color: reuse its prior port, else a fresh one.
	port := old.Ports[target]
	if port == 0 {
		apps, _ := listApps()
		port = pickPort(usedPorts(apps))
	}
	st.Ports = cloneColors(old.Ports)
	st.Ports[target] = port

	// Pull first so a bad image fails loud, before we touch units or routing — but only
	// when the digest isn't already on the box. Digest-pinned images are immutable, so a
	// present one is the right bits; skipping the pull keeps a redeploy/rollback of a
	// cached image working even if a registry credential has expired. A failed pull is
	// classified (registry_auth / registry_unreachable / image_not_found) so the caller
	// can settle an actionable outcome. See decisions/registry-credentials.md.
	if !imageExists(st.Image) {
		if err := pullImage(st.Image); err != nil {
			return err
		}
	}
	// Accessories first: the database has to be up and reachable before a migration can
	// run against it, let alone before the app boots. Idempotent — an accessory whose
	// unit is unchanged is left running, because restarting a database nobody asked to
	// change is an outage nobody asked for. They persist across the color flip below.
	if err := ensureAccessories(*st); err != nil {
		return err
	}
	// The declared release step, from the new image, before anything is written or
	// started. Here because a failure at this point changes nothing — no unit, no color,
	// the old one still serving — which is the same fail-safe the health gate gives one
	// step later. The cost is that the old code briefly meets the new schema, so
	// migrations must be backward-compatible for one release; that is the expand/contract
	// discipline blue/green requires, not something this invents. See release.go.
	if err := runRelease(*st); err != nil {
		return err
	}
	// Bring up the target color alongside the live one (boot-enabled).
	if err := writeUnit(*st, target, port, true); err != nil {
		return err
	}
	// A colour is the whole app, so the teardown on every failure below takes the
	// processes with it — a half-started colour is not a state anything should be left in.
	fail := func(format string, args ...any) error {
		teardownColorWith(st.Name, target, st.Processes)
		return fmt.Errorf(format, args...)
	}
	if err := daemonReload(); err != nil {
		return fail("daemon-reload: %w", err)
	}
	if err := userctl("start", serviceName(st.Name, target)); err != nil {
		return fail("start %s: %w", containerName(st.Name, target), err)
	}
	for _, p := range st.Processes {
		if err := userctl("start", processService(st.Name, p.Name, target)); err != nil {
			return fail("start %s: %w", processContainer(st.Name, p.Name, target), err)
		}
	}
	if err := waitHealthy(port, st.Health); err != nil {
		out, _ := podmanOutput("logs", "--tail", "20", containerName(st.Name, target))
		return fail("health check failed, old app left running: %w\n%s", err, out)
	}
	// A process has no port, so nothing can probe it — but a worker that dies on boot
	// would otherwise deploy "successfully" and simply never run, which is the failure
	// this whole design is meant not to have. `Restart=on-failure` would hide it as a
	// crash loop, so the unit is asked whether it is still up once the web side is
	// healthy. Not a health check: the weakest honest question, which is *is it running*.
	for _, p := range st.Processes {
		if err := userctl("is-active", "--quiet", processService(st.Name, p.Name, target)); err != nil {
			out, _ := podmanOutput("logs", "--tail", "20", processContainer(st.Name, p.Name, target))
			return fail("process %q did not stay up, old app left running:\n%s", p.Name, out)
		}
	}

	// Healthy — flip. Remember the outgoing image, set the live color, persist, route.
	if hadOld {
		st.PrevImage = old.Image
	}
	st.ActiveColor = target
	if err := saveApp(*st); err != nil {
		return fail("%w", err)
	}
	if err := refreshCaddy(); err != nil {
		return fmt.Errorf("route: %w", err)
	}

	// Retire the previous color, draining via TimeoutStopSec. The new one already serves.
	// Retired with *its own* processes, read off the spec that colour was deployed from —
	// a process dropped in this deploy still has a container to stop.
	if hadOld && old.ActiveColor != "" && old.ActiveColor != target {
		teardownColorWith(st.Name, old.ActiveColor, old.Processes)
		delete(st.Ports, old.ActiveColor)
		_ = saveApp(*st)
	}

	// The old colour's container is gone, so whatever it was running is now
	// unreferenced. Evict it — the image store is a cache, and the spec plus the
	// registry are the record (see prune.go). Deliberately last, deliberately silent
	// on failure: the app is already serving, and cleanup must never be able to fail
	// the act it follows.
	if _, note := pruneImages(); note != "" {
		fmt.Println(note)
	}
	return nil
}

func waitHealthy(hostPort int, path string) error {
	url := fmt.Sprintf("http://127.0.0.1:%d%s", hostPort, ensureLeadingSlash(path))
	client := &http.Client{Timeout: 3 * time.Second}
	var last string
	for i := 0; i < 15; i++ {
		resp, err := client.Get(url)
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode < 500 {
				return nil
			}
			last = fmt.Sprintf("status %d", resp.StatusCode)
		} else {
			last = err.Error()
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("not healthy at %s (%s)", url, last)
}

// --- rollback ---

func rollbackCmd(args []string) core.Result {
	_, pos := core.ParseArgs(args)
	name := firstPos(pos)
	if name == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	st, found := loadApp(name)
	if !found {
		return core.Result{Code: "not_found", Message: fmt.Sprintf("no app %q", name)}
	}
	if st.PrevImage == "" {
		return core.Result{Code: "no_previous", Message: "no last-good image to roll back to"}
	}
	st.Image = st.PrevImage
	return resultOrErr(withAppLock(name, func() error { return runDeploy(&st) }),
		"rollback_failed", fmt.Sprintf("rolled %q back to %s", name, shortDigest(st.Image)))
}

// --- lifecycle ---

func startCmd(args []string) core.Result   { return lifecycle("start", args) }
func stopCmd(args []string) core.Result    { return lifecycle("stop", args) }
func restartCmd(args []string) core.Result { return lifecycle("restart", args) }

// lifecycle drives the active color's user service. start/stop also flip whether the
// unit is boot-enabled, so a stop stays down across reboot and a start comes back —
// matching operator intent (generated Quadlet units can't be systemctl-disabled, so the
// [Install] section is rewritten instead).
func lifecycle(verb string, args []string) core.Result {
	_, pos := core.ParseArgs(args)
	app := firstPos(pos)
	if app == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	// start/stop rewrite the unit and restart drives the service — all three race a
	// deploy that is mid-flip, so they take the same lock it does.
	var res core.Result
	if err := withAppLock(app, func() error { res = lifecycleLocked(verb, app); return nil }); err != nil {
		return resultFromErr(err, verb+"_failed")
	}
	return res
}

func lifecycleLocked(verb, app string) core.Result {
	st, found := loadApp(app)
	if !found || st.ActiveColor == "" {
		return core.Result{Code: "not_found", Message: fmt.Sprintf("no running app %q", app)}
	}
	color := st.ActiveColor
	fail := func(err error) core.Result { return core.Result{Code: verb + "_failed", Message: err.Error()} }

	// A colour is the whole app, so a lifecycle verb drives all of it. Stopping an app
	// and leaving its worker running would be the drift these exist to prevent, arriving
	// by a different road. `writeUnit` already rewrites every process's unit with the
	// same [Install] section, so only the services need naming here.
	services := []string{serviceName(app, color)}
	for _, p := range st.Processes {
		services = append(services, processService(app, p.Name, color))
	}

	switch verb {
	case "start":
		if err := writeUnit(st, color, st.Ports[color], true); err != nil {
			return fail(err)
		}
		if err := daemonReload(); err != nil {
			return fail(err)
		}
	case "stop":
		// Rewrite without [Install] so the units aren't wanted at boot, then stop.
		if err := writeUnit(st, color, st.Ports[color], false); err != nil {
			return fail(err)
		}
		if err := daemonReload(); err != nil {
			return fail(err)
		}
	}
	for _, svc := range services {
		if err := userctl(verb, svc); err != nil {
			return fail(err)
		}
	}
	past := map[string]string{"start": "started", "stop": "stopped", "restart": "restarted"}[verb]
	return core.OK(fmt.Sprintf("%s %q", past, app))
}

func removeCmd(args []string) core.Result {
	_, pos := core.ParseArgs(args)
	app := firstPos(pos)
	if app == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	var res core.Result
	if err := withAppLock(app, func() error { res = removeLocked(app); return nil }); err != nil {
		return resultFromErr(err, "remove_failed")
	}
	return res
}

func removeLocked(app string) core.Result {
	st, found := loadApp(app)
	// Stop and remove both colors' units, then the accessories, then the secrets, then
	// the state.
	for _, color := range []string{colorA, colorB} {
		// Processes go with the colour they belong to — the whole app, not the web half.
		teardownColorWith(app, color, st.Processes)
	}
	// The accessories go with the app that owned them — they were never anything else's
	// to reach. Their **volumes stay**: undeclaring a database must not be how its data
	// disappears, and `remove` has its own opt-in for that.
	teardownAccessories(app)
	_ = daemonReload()
	if found {
		for _, name := range st.Secrets {
			_ = userExec("podman", "secret", "rm", secretRef(app, name)).Run()
		}
		for n := range st.SecretFiles {
			_ = userExec("podman", "secret", "rm", secretRef(app, n)).Run()
		}
		for _, a := range st.Accessories {
			for _, n := range a.Secrets {
				_ = userExec("podman", "secret", "rm", accessorySecretRef(app, a.Name, n)).Run()
			}
		}
	}
	if err := removeApp(app); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := refreshCaddy(); err != nil {
		return core.Result{Code: "route_error", Message: err.Error()}
	}
	return core.OK(fmt.Sprintf("removed %q", app))
}

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
	// Reload via the local admin API (no root): adapt the base Caddyfile, which imports
	// our fragment, and push it to the running Caddy on localhost:2019.
	return caddyReload()
}

// caddyReload applies the current config through Caddy's local admin API. It needs no
// root — any local user can reach localhost:2019 — so the steward user can do it.
func caddyReload() error {
	c := userExec("caddy", "reload", "--config", caddyfilePath(), "--adapter", "caddyfile")
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
		return "# Managed by steward. No apps deployed.\n"
	}
	var b strings.Builder
	for _, a := range apps {
		fmt.Fprintf(&b, "%s {\n\treverse_proxy 127.0.0.1:%d\n}\n\n", strings.Join(a.Hostnames, " "), a.livePort())
	}
	return b.String()
}

// --- app state (one JSON file per app) ---

// validAppName is the charset an app name may use. It is the same rule as a client
// name today, but they are different things and will drift; keeping them apart means
// neither one loosens the other by accident.
//

func appPath(name string) string { return filepath.Join(appsDir(), name+".json") }

// saveApp is the chokepoint the renderers stand behind: every app state that reaches a
// Caddy site block or a Quadlet unit was either just validated by stateFromSpec or
// loaded from a file that passed through here. It checks *renderability* rather than the
// full spec, because it is also on the path for state that came off disk — a `rollback`
// re-persists a spec the box already had, and re-writing it unchanged should not be the
// moment a policy rule introduced later condemns it.
func saveApp(st appState) error {
	if err := validateRenderable(st); err != nil {
		return fmt.Errorf("refusing to persist an invalid app state: %w", err)
	}
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		return err
	}
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(appPath(st.Name), b, 0o640)
}

func loadApp(name string) (appState, bool) {
	if !core.ValidAppName(name) {
		return appState{}, false
	}
	b, err := os.ReadFile(appPath(name))
	if err != nil {
		return appState{}, false
	}
	var st appState
	if json.Unmarshal(b, &st) != nil {
		return appState{}, false
	}
	return st, true
}

func removeApp(name string) error {
	if !core.ValidAppName(name) {
		return fmt.Errorf("refusing to remove state for invalid app name %q", name)
	}
	err := os.Remove(appPath(name))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func listApps() ([]appState, error) {
	entries, err := os.ReadDir(appsDir())
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var apps []appState
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		if st, ok := loadApp(strings.TrimSuffix(e.Name(), ".json")); ok {
			apps = append(apps, st)
		}
	}
	return apps, nil
}

// --- podman + small helpers ---

// podman and podmanOutput run through userExec so Podman runs rootless as the steward
// user (correct XDG_RUNTIME_DIR / HOME / cwd) — see quadlet.go.
func podman(args ...string) error {
	c := userExec("podman", args...)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

func podmanOutput(args ...string) (string, error) {
	out, err := userExec("podman", args...).CombinedOutput()
	return string(out), err
}

func firstPos(pos []string) string {
	if len(pos) > 0 {
		return pos[0]
	}
	return ""
}

func atoiDefault(s string, def int) int {
	if n, err := strconv.Atoi(s); err == nil {
		return n
	}
	return def
}

func ensureLeadingSlash(p string) string {
	if p == "" {
		return "/"
	}
	if !strings.HasPrefix(p, "/") {
		return "/" + p
	}
	return p
}

// validDigestPin checks what follows @sha256: is actually a digest, not merely that the
// marker is present. The common mistake is pasting a value that already carries its own
// "sha256:" prefix, which yields `…@sha256:sha256:abc…` — that satisfies a contains-check
// and then fails at the container runtime with "invalid reference format", which tells the
// operator nothing about what they did. Failing here, with the reason, is the whole point
// of validating before the act.
func validDigestPin(image string) error {
	i := strings.Index(image, "@sha256:")
	if i < 0 {
		return nil // the contains-check above already reported this
	}
	hex := image[i+len("@sha256:"):]
	if strings.HasPrefix(hex, "sha256:") {
		return fmt.Errorf("image digest is doubled (@sha256:sha256:…) — the value already "+
			"carried its own prefix; use %s", strings.Replace(image, "@sha256:sha256:", "@sha256:", 1))
	}
	if len(hex) != 64 {
		return fmt.Errorf("image digest must be 64 hex characters, got %d", len(hex))
	}
	for _, r := range hex {
		if !(r >= '0' && r <= '9') && !(r >= 'a' && r <= 'f') {
			return fmt.Errorf("image digest has a non-hex character %q", r)
		}
	}
	return nil
}

func shortDigest(image string) string {
	if i := strings.Index(image, "@sha256:"); i >= 0 {
		h := image[i+len("@sha256:"):]
		if len(h) > 12 {
			return "sha256:" + h[:12]
		}
		return "sha256:" + h
	}
	return image
}
