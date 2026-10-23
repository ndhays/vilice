package app

// rollback, start/stop/restart and remove — the verbs on an app already deployed.

import (
	"vilice/internal/core"

	"fmt"
)

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
	removeUpdate(app) // its last update goes with it; a later app of the same name starts clean
	if err := removeApp(app); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := refreshCaddy(); err != nil {
		return core.Result{Code: "route_error", Message: err.Error()}
	}
	return core.OK(fmt.Sprintf("removed %q", app))
}
