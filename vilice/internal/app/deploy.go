package app

// `deploy` and the app lifecycle (operate scope). Wide, not deep: a state machine
// over borrowed muscle — Podman runs the container, Caddy routes to it. Failures are
// loud and recoverable; a failed deploy leaves the running app untouched. v1 cutover
// is non-gapless. See blueprint/vilice/deploy.md.

import (
	"vilice/internal/core"

	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
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
	// StopFirst stops the old colour before the new one starts, for an app that cannot
	// run twice over its own data (it locks it). Costs a gap in service. See runDeploy.
	StopFirst bool   `json:"stop_first,omitempty"`
	Digest    string `json:"digest,omitempty"` // sha256 of the canonical spec (sans secret values)
	HostPort  int    `json:"host_port"`        // legacy single-container port (pre-Quadlet); see livePort
	PrevImage string `json:"prev_image"`       // last-good before this one, for rollback

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
	// Vilice database-agnostic — the app owns its own consistency. See backup.go.
	Backup string `json:"backup,omitempty"`
	// StopFirst trades blue/green for stop-then-start: the old colour is stopped before
	// the release step and the new colour, so two copies never hold the data at once.
	// For apps that lock their data dir (a BoltDB cache, LMDB). A gap in service.
	StopFirst bool `json:"stop_first,omitempty"`
}

// deployEnvelope is one sweep: the full spec plus the secret values it needs. The
// spec is recorded (by digest, sans values); secret_values are bound and never recorded.
type deployEnvelope struct {
	App          appSpec           `json:"app"`
	SecretValues map[string]string `json:"secret_values,omitempty"`
}

func appsDir() string {
	if p := os.Getenv("VILICE_APPS_DIR"); p != "" {
		return p
	}
	return "/var/lib/vilice/apps"
}

// caddyfilePath is the base config the system Caddy loads (root-owned); it imports the
// vilice-owned fragment. caddyFragmentPath is the file Vilice actually writes — its
// app routes, under /etc/caddy/vilice/ so the caddy user can still read them.
func caddyfilePath() string {
	if p := os.Getenv("VILICE_CADDYFILE"); p != "" {
		return p
	}
	return "/etc/caddy/Caddyfile"
}

func caddyFragmentPath() string {
	if p := os.Getenv("VILICE_CADDY_FRAGMENT"); p != "" {
		return p
	}
	return "/etc/caddy/vilice/apps.caddy"
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
// rather than block. Vilice Console always pipes the envelope on the scoped-SSH call.
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
		Backup: s.Backup, StopFirst: s.StopFirst,
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
		// How the app is replaced is part of the deploy. omitempty so every spec
		// written before the field existed keeps the digest it was recorded under.
		StopFirst bool `json:"stop_first,omitempty"`
	}{st.Image, host, st.Port, st.Health, st.Env, sec, st.SecretFiles, vol, st.Release,
		st.Accessories, st.Processes, st.Backup, st.StopFirst}
	b, _ := json.Marshal(canonical) // map keys marshal sorted → deterministic
	sum := sha256.Sum256(b)
	return "sha256:" + hex.EncodeToString(sum[:])
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
	// stop_first: an app that locks its data cannot start beside itself — the new colour
	// waits on a lock the old one never lets go, and the health check times out. So the
	// old colour is stopped here, before the release step (which mounts the same volumes)
	// and before the new colour. Its unit stays, so a failure below can start it again.
	// Only a colour that was running is restarted: an app the operator stopped stays down.
	stopped := false
	if st.StopFirst && hadOld && old.ActiveColor != "" && old.ActiveColor != target {
		if userctl("is-active", "--quiet", serviceName(st.Name, old.ActiveColor)) == nil {
			stopColor(st.Name, old.ActiveColor, old.Processes)
			stopped = true
		}
	}
	left := leftBehind(hadOld)
	if stopped {
		left = "old app restarted"
	}
	// restore brings the stopped colour back after a failure, and says so if it can't —
	// with stop_first a failed deploy is an outage until someone starts the app.
	restore := func(err error) error {
		if !stopped {
			return err
		}
		if rerr := startColor(st.Name, old.ActiveColor, old.Processes); rerr != nil {
			return fmt.Errorf("%w\nthe old app was stopped first (stop_first) and did not start again: %v — try: vilice start %s",
				err, rerr, st.Name)
		}
		return err
	}
	// The declared release step, from the new image, before anything is written or
	// started. Here because a failure at this point changes nothing — no unit, no color,
	// the old one still serving — which is the same fail-safe the health gate gives one
	// step later. The cost is that the old code briefly meets the new schema, so
	// migrations must be backward-compatible for one release; that is the expand/contract
	// discipline blue/green requires, not something this invents. See release.go.
	if err := runRelease(*st); err != nil {
		return restore(err)
	}
	// Bring up the target color alongside the live one (boot-enabled).
	if err := writeUnit(*st, target, port, true); err != nil {
		return restore(err)
	}
	// A colour is the whole app, so the teardown on every failure below takes the
	// processes with it — a half-started colour is not a state anything should be left in.
	fail := func(format string, args ...any) error {
		teardownColorWith(st.Name, target, st.Processes)
		return restore(fmt.Errorf(format, args...))
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
	// The app's last words, kept while the container is still there to ask. A container
	// that dies at boot is removed with its logs, so asking only after the wait has failed
	// finds nothing — which is how a failed first deploy came back with no reason at all.
	var logs string
	keepLogs := func() {
		if out, err := podmanOutput("logs", "--tail", "20", containerName(st.Name, target)); err == nil && strings.TrimSpace(out) != "" {
			logs = out
		}
	}
	if err := waitHealthy(port, st.Health, keepLogs); err != nil {
		keepLogs()
		// The address in the error is the loopback port this box publishes the app on,
		// not the port the app was told to listen on. Say both, or an operator who
		// asked for 8080 reads 8800 as a port they never chose.
		return fail("health check failed, %s: %s%w\n127.0.0.1:%d is where this box publishes the app's port %d\n%s",
			left, lowPortHint(logs, st.Port), err, port, st.Port, logs)
	}
	// A process has no port, so nothing can probe it — but a worker that dies on boot
	// would otherwise deploy "successfully" and simply never run, which is the failure
	// this whole design is meant not to have. `Restart=on-failure` would hide it as a
	// crash loop, so the unit is asked whether it is still up once the web side is
	// healthy. Not a health check: the weakest honest question, which is *is it running*.
	for _, p := range st.Processes {
		if err := userctl("is-active", "--quiet", processService(st.Name, p.Name, target)); err != nil {
			out, _ := podmanOutput("logs", "--tail", "20", processContainer(st.Name, p.Name, target))
			return fail("process %q did not stay up, %s:\n%s", p.Name, left, out)
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

// leftBehind says what a failed deploy left on the box. A first deploy has no old app
// to keep serving, and saying it does sends the operator looking for one.
func leftBehind(hadOld bool) string {
	if hadOld {
		return "old app left running"
	}
	return "nothing is deployed"
}

// The ways a program says it was refused a port, each with the port it asked for: Go
// ("listen tcp :80: bind: permission denied"), nginx ("bind() to 0.0.0.0:80 failed (13:
// Permission denied)"), and Node ("listen EACCES: permission denied 0.0.0.0:80"). Exact
// shapes on purpose — a looser match would read a timestamp as a port.
var lowPortRefusals = []*regexp.Regexp{
	regexp.MustCompile(`:(\d{1,5}): bind: permission denied`),
	regexp.MustCompile(`:(\d{1,5}) failed \(13: Permission denied\)`),
	regexp.MustCompile(`EACCES: permission denied [^\s:]*:(\d{1,5})\b`),
}

// lowPortHint names the commonest reason a first deploy never answers: the app tried to
// listen on a port below 1024, which a container here cannot do. Vilice refuses such a
// port in the spec, but the spec only says where to *reach* the app — the app picks
// where it listens, and many images default to 80. Returns "" when the logs do not say
// so; it is read off the app's own words, never guessed.
func lowPortHint(logs string, port int) string {
	for _, re := range lowPortRefusals {
		m := re.FindStringSubmatch(logs)
		if m == nil {
			continue
		}
		if n, err := strconv.Atoi(m[1]); err == nil && n > 0 && n < 1024 {
			return fmt.Sprintf("the app tried to listen on port %d, and a container here cannot use a port below 1024. "+
				"Make it listen on %d — for a Rails image with Thruster, set HTTP_PORT=%d.\n", n, port, port)
		}
	}
	return ""
}

// waitHealthy polls the app until it answers. each runs once per try, while the
// container may still exist.
func waitHealthy(hostPort int, path string, each func()) error {
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
		each()
		time.Sleep(time.Second)
	}
	return fmt.Errorf("not healthy at %s (%s)", url, last)
}

// --- podman + small helpers ---

// podman and podmanOutput run through userExec so Podman runs rootless as the vilice
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
