package app

// `logs` (observe): tail an app's logs. A thin passthrough to `podman logs`; the
// container is the source of truth, so there's nothing for Steward to store.

import (
	"steward/internal/core"

	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

func logsCmd(args []string) core.Result {
	app, tail := parseLogsArgs(args)
	if app == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	if _, err := exec.LookPath("podman"); err != nil {
		return core.Result{Code: "unavailable", Message: "podman not found"}
	}
	// Logs come from the live color's container; read through the user-context seam.
	st, found := loadApp(app)
	if !found || st.ActiveColor == "" {
		return core.Result{Code: "not_found", Message: fmt.Sprintf("no running app %q", app)}
	}

	cargs := []string{"logs"}
	if tail > 0 {
		cargs = append(cargs, "--tail", strconv.Itoa(tail))
	}
	cargs = append(cargs, containerName(app, st.ActiveColor))

	out, err := podmanOutput(cargs...)
	if err != nil {
		return core.Result{Code: "logs_failed", Message: strings.TrimSpace(out)}
	}
	return core.Result{Code: "ok", Message: strings.TrimRight(out, "\n")}
}

// parseLogsArgs pulls the app name and an optional -n/--tail count out of args.
func parseLogsArgs(args []string) (app string, tail int) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "-n", "--tail":
			if i+1 < len(args) {
				tail, _ = strconv.Atoi(args[i+1])
				i++
			}
		default:
			if !strings.HasPrefix(args[i], "-") && app == "" {
				app = args[i]
			}
		}
	}
	return app, tail
}
