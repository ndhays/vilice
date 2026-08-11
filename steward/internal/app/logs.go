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
	app, tail, err := parseLogsArgs(args)
	if err != nil {
		return core.Result{Code: "bad_args", Message: err.Error()}
	}
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

// parseLogsArgs pulls the app name and an optional -n/--tail count out of args,
// through core.ParseArgs — the same parser every other command uses.
//
// It had its own parser once, matching whole tokens, and so accepted `--tail 100`
// but silently dropped `--tail=100`: the gate admits both spellings (it splits on
// `=` to check the name is declared), and the second one arrived here as a token
// matching nothing. You asked for a hundred lines and got the whole log. One parser
// is the fix; a second parser is how it happened.
//
// `-n` never reaches here: it is declared as the flag's Alias and the gate rewrites
// it, so this sees one spelling.
func parseLogsArgs(args []string) (app string, tail int, err error) {
	flags, pos := core.ParseArgs(args)

	// A tail that isn't a line count is refused rather than rounded down to "all of
	// it". Silently printing the whole log because the count was a typo is the same
	// failure the parser bug caused, arriving by a different road.
	if v, ok := flags["tail"]; ok {
		n, convErr := strconv.Atoi(v)
		if convErr != nil || n < 0 {
			return "", 0, fmt.Errorf("--tail wants a line count, got %q", v)
		}
		tail = n
	}
	return firstPos(pos), tail, nil
}
