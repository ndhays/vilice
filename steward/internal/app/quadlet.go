package app

// Quadlet unit generation and blue/green bookkeeping — the pure core of the deploy
// rearchitecture (see decisions/open/quadlet-units.md). An app runs as a rootless
// systemd Quadlet `.container` unit under the `steward` user; deploys alternate two
// colors so a failed deploy never touches the running one.
//
// This file is the offline-testable half: rendering a unit, choosing the next color,
// and allocating a stable loopback port. The `systemctl --user` / daemon-reload
// integration that consumes it is the on-box half.

import (
	"steward/internal/core"

	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
)

// --- the user-context exec seam ---
//
// Steward runs as the unprivileged `steward` user (see decisions/ceiling-is-the-machine.md),
// so its rootless Podman and `systemctl --user` manager live under that user's session.
// Reaching them needs XDG_RUNTIME_DIR (the user bus), HOME, and a cwd the user can read.
// Depending on how Steward was launched — the sshd forced command or `sudo -u steward` —
// these may be unset or point at root's, so we set them explicitly. Every podman and
// systemctl --user call goes through here, so the user context is defined in one place.

func userHome() string {
	if u, err := user.LookupId(strconv.Itoa(os.Geteuid())); err == nil {
		return u.HomeDir
	}
	return "/home/" + core.StewardUser
}

// userExec builds a command wired to the steward user's session: XDG_RUNTIME_DIR + HOME
// set from the effective uid, and cwd at the user's home.
func userExec(name string, args ...string) *exec.Cmd {
	c := exec.Command(name, args...)
	home := userHome()
	env := setEnv(os.Environ(), "XDG_RUNTIME_DIR", fmt.Sprintf("/run/user/%d", os.Geteuid()))
	env = setEnv(env, "HOME", home)
	// Point every podman call at the persistent auth file, so a registry login survives
	// reboot (podman's default lives under XDG_RUNTIME_DIR, a tmpfs). See registry.go.
	env = setEnv(env, "REGISTRY_AUTH_FILE", authFilePath())
	c.Env = env
	c.Dir = home
	return c
}

// setEnv replaces or appends KEY=val in an environment slice.
func setEnv(env []string, key, val string) []string {
	prefix := key + "="
	for i, e := range env {
		if strings.HasPrefix(e, prefix) {
			env[i] = prefix + val
			return env
		}
	}
	return append(env, prefix+val)
}

// drainTimeoutSecs is the unit's TimeoutStopSec — the single drain knob. After the
// Caddy flip the old color gets SIGTERM and this long to finish in-flight work and
// exit; then it's killed. See the app shutdown contract in deploy.md.
const drainTimeoutSecs = 30

// appOOMScoreAdjust biases the kernel OOM killer toward app containers, so under memory
// pressure an app dies before the control plane (Caddy, sshd, the record), which sit at
// the default 0. Positive = more killable. A later spec field can override it per app
// (e.g. a protective negative value for Steward Console when it runs on the managed box).
const appOOMScoreAdjust = 100

// drainingOOMScoreAdjust makes a retiring color the first OOM victim during the brief
// blue/green overlap — it's being torn down anyway, so the live color must outlive it.
const drainingOOMScoreAdjust = 1000

// portBase is the low end of the loopback port range steward manages for app colors.
const portBase = 8800

const colorA, colorB = "a", "b"

// otherColor returns the color to deploy into: the opposite of the active one. The
// empty active (first deploy) and color "b" both yield "a".
func otherColor(active string) string {
	if active == colorA {
		return colorB
	}
	return colorA
}

// containerName / unitFileName name a color's container and its Quadlet file. The
// `.container` file <app>-<color>.container becomes the <app>-<color>.service unit.
func containerName(app, color string) string { return app + "-" + color }
func unitFileName(app, color string) string  { return containerName(app, color) + ".container" }
func serviceName(app, color string) string   { return containerName(app, color) + ".service" }

// quadletDir is where rootless user units live: ~steward/.config/containers/systemd/.
// The home is resolved from the effective user (passwd db), so it's correct under
// `sudo -u steward` where $HOME may still be root's — same approach as auth.go.
func quadletDir() (string, error) {
	if p := os.Getenv("STEWARD_QUADLET_DIR"); p != "" {
		return p, nil
	}
	u, err := user.LookupId(strconv.Itoa(os.Geteuid()))
	if err != nil {
		return "", err
	}
	return filepath.Join(u.HomeDir, ".config", "containers", "systemd"), nil
}

// usedPorts collects every host port already assigned across all apps and colors, so a
// new color's port doesn't collide with one we've already handed out.
func usedPorts(apps []appState) map[int]bool {
	used := map[int]bool{}
	for _, a := range apps {
		for _, p := range a.Ports {
			if p != 0 {
				used[p] = true
			}
		}
	}
	return used
}

// pickPort returns the lowest free steward port (>= portBase) not in used. It allocates
// only against state we already track; that an unrelated process isn't bound to the
// number is an on-box check (the deploy tries to bring the unit up and fails loud).
func pickPort(used map[int]bool) int {
	p := portBase
	for used[p] {
		p++
	}
	return p
}

// renderQuadletUnit is pure: the rootless `.container` file for one color of an app,
// published on a fixed loopback host port. Env, secrets (by name, from the Podman
// secret store), and volumes come straight from the declared spec. enabled controls the
// [Install] section: with it the unit starts at boot (WantedBy=default.target); without
// it the unit stays down across reboots — how `stop` persists (generated units can't be
// `systemctl disable`d).
func renderQuadletUnit(st appState, color string, hostPort int, enabled bool) string {
	var b strings.Builder
	b.WriteString("# Managed by steward. Generated from app-state — do not edit.\n")
	b.WriteString("[Unit]\n")
	fmt.Fprintf(&b, "Description=Steward app %s (%s)\n\n", st.Name, color)

	b.WriteString("[Container]\n")
	fmt.Fprintf(&b, "Image=%s\n", st.Image)
	fmt.Fprintf(&b, "ContainerName=%s\n", containerName(st.Name, color))
	fmt.Fprintf(&b, "PublishPort=127.0.0.1:%d:%d\n", hostPort, st.Port)
	// Only when this app declares accessories, because only then does the network exist.
	// Both colors join the same one, so a flip does not disturb what the database sees —
	// and nothing else on the box ever joins it, which is what makes "web can reach db"
	// stop short of "anything can reach db". See accessory.go.
	if len(st.Accessories) > 0 {
		fmt.Fprintf(&b, "Network=%s\n", accessoryNetwork(st.Name))
	}
	fmt.Fprintf(&b, "Environment=%s\n", quoteEnv("PORT", strconv.Itoa(st.Port)))
	for _, k := range sortedKeys(st.Env) {
		fmt.Fprintf(&b, "Environment=%s\n", quoteEnv(k, st.Env[k]))
	}
	for _, name := range st.Secrets {
		fmt.Fprintf(&b, "Secret=%s,type=env,target=%s\n", secretRef(st.Name, name), name)
	}
	for _, name := range sortedKeys(st.SecretFiles) {
		fmt.Fprintf(&b, "Secret=%s,type=mount,target=%s\n", secretRef(st.Name, name), st.SecretFiles[name])
	}
	for _, v := range st.Volumes {
		fmt.Fprintf(&b, "Volume=%s\n", v)
	}

	// ── The ceiling on what the app may do ────────────────────────────────────
	// Rootless already means container-root maps to the `steward` user and not the
	// host's, so an escape lands in an unprivileged account. These two lines narrow
	// what is left, and both are chosen to cost a well-behaved image nothing — a
	// hardening default that breaks ordinary apps is one that gets turned off.
	//
	// NoNewPrivileges blocks the single way a process inside gains a privilege it was
	// not started with: a setuid binary or a file capability, at execve. Dropping
	// *to* an unprivileged user — the gosu/su-exec entrypoint pattern — is a syscall
	// and not an execve gain, so that still works. What stops working is `sudo`,
	// which an app server has no business calling.
	//
	// The dropped capabilities are the ones an app cannot justify. NET_BIND_SERVICE
	// is the clearest: `deploy` already refuses a port below 1024, so the capability
	// to bind one is *provably* unnecessary here — a ceiling that matches a rule we
	// already enforce, rather than a guess about what apps need. SETFCAP and SETPCAP
	// hand out capabilities and SYS_CHROOT is a sandbox-escape primitive; none is
	// reachable from serving HTTP. What an ordinary entrypoint does need is left
	// alone: CHOWN for a data directory, SETUID/SETGID to drop privileges, KILL to
	// signal a child.
	b.WriteString("NoNewPrivileges=true\n")
	b.WriteString("DropCapability=CAP_NET_BIND_SERVICE CAP_SETFCAP CAP_SETPCAP CAP_SYS_CHROOT\n")

	b.WriteString("\n[Service]\n")
	// SIGTERM (Podman's default stop signal) starts the app's drain; TimeoutStopSec
	// bounds it before SIGKILL. Restart=on-failure brings a crashed app back.
	fmt.Fprintf(&b, "TimeoutStopSec=%d\n", drainTimeoutSecs)
	b.WriteString("Restart=on-failure\n")
	// Protect the control plane: an app is a preferred OOM victim over system services.
	fmt.Fprintf(&b, "OOMScoreAdjust=%d\n", appOOMScoreAdjust)

	if enabled {
		b.WriteString("\n[Install]\nWantedBy=default.target\n")
	}
	return b.String()
}

// quoteEnv renders one systemd Environment= assignment, double-quoting the value so
// spaces and shell metacharacters survive. Backslashes and quotes are escaped.
func quoteEnv(key, val string) string {
	esc := strings.ReplaceAll(val, `\`, `\\`)
	esc = strings.ReplaceAll(esc, `"`, `\"`)
	return fmt.Sprintf(`"%s=%s"`, key, esc)
}

// --- unit files + systemctl --user ---

// userctl runs `systemctl --user <args>` in the steward user's session.
func userctl(args ...string) error {
	c := userExec("systemctl", append([]string{"--user"}, args...)...)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

func daemonReload() error { return userctl("daemon-reload") }

// writeUnit renders and writes a color's .container file into the quadlet dir. A
// daemon-reload after this turns it into the <app>-<color>.service unit.
func writeUnit(st appState, color string, port int, enabled bool) error {
	// The render boundary: a unit file is line-oriented, so every value going into it is
	// checked for anything that could end its line — including on paths that never
	// touched deploy, like a spec read back off disk. Whether the volume may point where
	// it points is policy, settled at the doors (validateState).
	// See decisions/rendered-config-is-a-boundary.md.
	if err := validateRenderable(st); err != nil {
		return fmt.Errorf("refusing to write a unit from an invalid app state: %w", err)
	}
	dir, err := quadletDir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, unitFileName(st.Name, color)),
		[]byte(renderQuadletUnit(st, color, port, enabled)), 0o644); err != nil {
		return err
	}
	// A colour is the whole app: the web container plus every declared process, written
	// together so they can only ever come up at one digest (process.go).
	for _, proc := range st.Processes {
		if err := os.WriteFile(filepath.Join(dir, processUnitFile(st.Name, proc.Name, color)),
			[]byte(renderProcessUnit(st, proc, color, enabled)), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// removeUnit deletes a color's .container file (no error if already gone).
func removeUnit(app, color string) error {
	if !core.ValidAppName(app) {
		return fmt.Errorf("refusing to remove a unit for invalid app name %q", app)
	}
	dir, err := quadletDir()
	if err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(dir, unitFileName(app, color))); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// teardownColor stops a color's service (SIGTERM, drained by TimeoutStopSec) and removes
// its unit, then reloads. Best-effort — used to retire the old color after a flip and to
// clean up a new color whose deploy failed.
func teardownColor(app, color string) {
	teardownColorWith(app, color, nil)
}

// teardownColorWith retires a colour and the processes that belong to it. `procs` is
// nil where the caller has no spec in hand — `remove` sweeps by filename instead, so a
// process whose declaration has already gone is still cleaned up.
func teardownColorWith(app, color string, procs []Process) {
	// Make the doomed color the first OOM victim during its drain, so memory pressure in
	// the overlap can't take the live color instead. Best-effort, runtime-only.
	_ = userctl("set-property", serviceName(app, color), fmt.Sprintf("OOMScoreAdjust=%d", drainingOOMScoreAdjust))
	_ = userctl("stop", serviceName(app, color))
	_ = removeUnit(app, color)
	for _, p := range procs {
		_ = userctl("stop", processService(app, p.Name, color))
		_ = removeProcessUnit(app, p.Name, color)
	}
	_ = daemonReload()
}

// removeProcessUnit deletes one process colour's .container file (no error if gone).
func removeProcessUnit(app, name, color string) error {
	if !core.ValidAppName(app) || !core.ValidAppName(name) {
		return fmt.Errorf("refusing to remove a unit for invalid names %q/%q", app, name)
	}
	dir, err := quadletDir()
	if err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(dir, processUnitFile(app, name, color))); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// cloneColors copies a color->port map (nil-safe, always returns a usable map).
func cloneColors(m map[string]int) map[string]int {
	out := make(map[string]int, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
