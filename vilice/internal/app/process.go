package app

// Processes: the worker, the clock, anything an app runs that the world does not reach.
//
// **The same code, so the same deploy.** A worker is not a second app — it is the app's
// image, its env, its secrets and its volumes, running a different command. That is the
// whole reason it is a field on the spec rather than a second install: if web and worker
// could be deployed separately, nothing would stop them drifting onto different digests,
// and a worker running yesterday's code against today's enqueued jobs is a failure the
// record could not even describe. One spec, one digest, one deploy — they cannot skew.
//
// **A colour is the whole app.** Before this, a colour was one container. It is now the
// web container *plus every declared process*, brought up together and retired together,
// so the flip stays exactly what it was: one set of containers replaces another. That is
// also why processes are blue/green rather than replaced in place — one mechanism, not
// two, and during the overlap you have old-web with old-worker and new-web with
// new-worker, never a mixture.
//
// **Not accessories.** An accessory is something the app *depends on* — a database, with
// its own image and its own data, single and persistent across flips. A process *is* the
// app. The two look alike from a distance and behave oppositely on every axis that
// matters.

import (
	"fmt"
	"strings"

	"vilice/internal/core"
)

// Process is one non-web process of an app. Deliberately tiny: everything except the
// command is inherited, because the point is that it cannot differ from the web process
// in any way that would let the two drift.
type Process struct {
	Name string `json:"name"`
	// Command is **argv, never a shell** — the same rule the release step follows, for
	// the same reasons: the recorded line is unambiguous, and anything needing a shell
	// belongs in a script inside the image where the digest covers it.
	Command []string `json:"command"`
}

func processContainer(app, name, color string) string { return app + "-" + name + "-" + color }
func processUnitFile(app, name, color string) string {
	return processContainer(app, name, color) + ".container"
}
func processService(app, name, color string) string {
	return processContainer(app, name, color) + ".service"
}

// validProcesses checks the declaration, and then checks the whole app for container-name
// collisions in one place — processes, accessories and colours all mint names from the
// app's, and two of them landing on one name would have each quietly overwrite the
// other's unit file.
func validProcesses(st appState) error {
	seen := map[string]bool{}
	for _, p := range st.Processes {
		switch {
		case !core.ValidAppName(p.Name):
			return fmt.Errorf("process name %q must be [A-Za-z0-9_-]", p.Name)
		case p.Name == st.Name:
			return fmt.Errorf("process %q may not share its app's name", p.Name)
		case seen[p.Name]:
			return fmt.Errorf("process %q is declared twice", p.Name)
		case len(p.Command) == 0:
			return fmt.Errorf("process %q has no command — that is the only thing that makes it one", p.Name)
		}
		if err := validRelease(p.Command); err != nil {
			return fmt.Errorf("process %q: %w", p.Name, err)
		}
		seen[p.Name] = true
	}
	return containerNamesAreDistinct(st)
}

// containerNamesAreDistinct enumerates every container this app will ever create and
// refuses a duplicate. Checking the *names* rather than the rules that generate them
// means a new kind of container is covered the day it is added.
func containerNamesAreDistinct(st appState) error {
	seen := map[string]string{}
	claim := func(name, what string) error {
		if prev, taken := seen[name]; taken {
			return fmt.Errorf("%s and %s would both be container %q", prev, what, name)
		}
		seen[name] = what
		return nil
	}
	for _, color := range []string{colorA, colorB} {
		if err := claim(containerName(st.Name, color), "the "+color+" colour"); err != nil {
			return err
		}
		for _, p := range st.Processes {
			if err := claim(processContainer(st.Name, p.Name, color), "process "+p.Name); err != nil {
				return err
			}
		}
	}
	for _, a := range st.Accessories {
		if err := claim(accessoryContainer(st.Name, a.Name), "accessory "+a.Name); err != nil {
			return err
		}
	}
	return nil
}

// renderProcessUnit is pure: the rootless `.container` file for one process of one
// colour. It is the app's own unit minus the two things only a served process needs — a
// published port and a health path — plus the command that makes it a different process.
func renderProcessUnit(st appState, p Process, color string, enabled bool) string {
	var b strings.Builder
	b.WriteString("# Managed by vilice. Generated from app-state — do not edit.\n")
	b.WriteString("[Unit]\n")
	fmt.Fprintf(&b, "Description=Vilice process %s of %s (%s)\n\n", p.Name, st.Name, color)

	b.WriteString("[Container]\n")
	fmt.Fprintf(&b, "Image=%s\n", st.Image)
	fmt.Fprintf(&b, "ContainerName=%s\n", processContainer(st.Name, p.Name, color))
	// **No PublishPort.** Nothing reaches a worker from outside, and Caddy is never told
	// it exists. If it needs to talk to an accessory it does so on the app's network,
	// which it joins for the same reason the web container does.
	if len(st.Accessories) > 0 {
		fmt.Fprintf(&b, "Network=%s\n", accessoryNetwork(st.Name))
	}
	// Argv, one element per line — systemd splits Exec= on whitespace, so a value that
	// contained a space would otherwise become two arguments.
	fmt.Fprintf(&b, "Exec=%s\n", strings.Join(quoteExec(p.Command), " "))
	// PORT is still exported: the image is the same one, and something in it may read
	// the variable even in a process that never binds.
	fmt.Fprintf(&b, "Environment=%s\n", quoteEnv("PORT", fmt.Sprint(st.Port)))
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
	b.WriteString("NoNewPrivileges=true\n")
	b.WriteString("DropCapability=CAP_NET_BIND_SERVICE CAP_SETFCAP CAP_SETPCAP CAP_SYS_CHROOT\n")

	b.WriteString("\n[Service]\n")
	fmt.Fprintf(&b, "TimeoutStopSec=%d\n", drainTimeoutSecs)
	b.WriteString("Restart=on-failure\n")
	fmt.Fprintf(&b, "OOMScoreAdjust=%d\n", appOOMScoreAdjust)
	if enabled {
		b.WriteString("\n[Install]\nWantedBy=default.target\n")
	}
	return b.String()
}

// quoteExec double-quotes each argv element, so an argument containing a space stays one
// argument. systemd splits Exec= on whitespace otherwise — the same trap quoteEnv exists
// for, one directive over.
func quoteExec(argv []string) []string {
	out := make([]string, 0, len(argv))
	for _, a := range argv {
		esc := strings.ReplaceAll(a, `\`, `\\`)
		esc = strings.ReplaceAll(esc, `"`, `\"`)
		out = append(out, `"`+esc+`"`)
	}
	return out
}
