package app

// Routing this box to *other* boxes — the edge half of the pack.
//
// Every route the pack writes elsewhere is `reverse_proxy 127.0.0.1:<port>`, derived
// from the apps on this machine. That is the right answer for an app served off its own
// box, and it cannot express the other shape: one box fronting several others, with a
// hostname whose upstreams live somewhere else entirely.
//
// `route` is that shape. It takes a routing table on stdin, exactly as `deploy` takes a
// spec, and writes a second Caddy fragment beside the app one. The base config written by
// `prepare` already imports the whole directory (`import /etc/caddy/steward/*.caddy`), so
// nothing about the substrate changes to accommodate this — the extension point was
// already there, and the system Caddy already holds 80/443.
//
// **The table is wholly declarative and wholly replaced.** There is no add-a-route or
// drop-a-route: you send what the box should serve, and that becomes what it serves. Same
// rule as `deploy` (declarative-deploy.md), for the same reason — a partial edit needs the
// caller and the box to agree about a starting state they cannot both see.
//
// Upstream addresses are **not** secret, so the table rides the recorded envelope rather
// than the off-record channel. What a box fronts is exactly the sort of thing the record
// should be able to answer later.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"steward/internal/core"
)

// routeTable is the declared desired state for this box's edge: what it fronts, and
// where each of those hostnames should be sent.
type routeTable struct {
	Routes []route `json:"routes"`
}

type route struct {
	// One or more site addresses that share these upstreams, as Caddy expects.
	Hostnames []string `json:"hostnames"`
	// Where to send them: `host:port`, one per backend box. More than one is a
	// load-balanced set; Caddy spreads across them itself.
	Upstreams []string `json:"upstreams"`
}

// routesFragmentPath is the file this verb owns. It sits in the same steward-owned
// directory as the app fragment and is picked up by the same glob import, so the two
// never touch each other: `deploy` rewrites apps.caddy, `route` rewrites this, and
// neither can clobber the other's routes.
func routesFragmentPath() string {
	if p := os.Getenv("STEWARD_CADDY_ROUTES"); p != "" {
		return p
	}
	return "/etc/caddy/steward/routes.caddy"
}

func routeCmd(args []string) core.Result {
	data, err := readStdinSpec(os.Stdin)
	if err != nil {
		return core.Result{Code: "bad_args", Message: "no routing table on stdin"}
	}

	var tbl routeTable
	if err := json.Unmarshal(data, &tbl); err != nil {
		return core.Result{Code: "bad_args", Message: fmt.Sprintf("routing table is not valid JSON: %v", err)}
	}
	if err := validateTable(tbl); err != nil {
		return core.Result{Code: "bad_args", Message: err.Error()}
	}

	// Validate first, then write. A table we refuse leaves the previous fragment in
	// place — the box keeps serving what it was serving, rather than losing its routes
	// to a malformed request. Same order as refreshCaddy, for the same reason.
	if err := os.MkdirAll(filepath.Dir(routesFragmentPath()), 0o755); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := os.WriteFile(routesFragmentPath(), []byte(renderRoutes(tbl)), 0o644); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := caddyReload(); err != nil {
		return core.Result{Code: "reload_failed", Retryable: true, Message: err.Error()}
	}

	if len(tbl.Routes) == 0 {
		return core.OK("routing table cleared — this box fronts nothing")
	}
	return core.OK(fmt.Sprintf("routing %s", strings.Join(summarize(tbl), ", ")))
}

func summarize(tbl routeTable) []string {
	out := make([]string, 0, len(tbl.Routes))
	for _, r := range tbl.Routes {
		out = append(out, fmt.Sprintf("%s → %d upstream%s",
			strings.Join(r.Hostnames, " "), len(r.Upstreams), plural(len(r.Upstreams))))
	}
	return out
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// An empty table is valid and means "front nothing" — that is how an operator takes a
// box out of service, and refusing it would leave no way to do so.
func validateTable(tbl routeTable) error {
	seen := map[string]bool{}
	for _, r := range tbl.Routes {
		if len(r.Hostnames) == 0 {
			return fmt.Errorf("a route has no hostnames")
		}
		if len(r.Upstreams) == 0 {
			return fmt.Errorf("route %q has no upstreams — a hostname routed nowhere is a 502 with extra steps",
				strings.Join(r.Hostnames, " "))
		}
		for _, h := range r.Hostnames {
			if err := validHostname(h); err != nil {
				return err
			}
			// Two routes claiming one hostname is ambiguous, and Caddy would resolve it
			// silently. Refuse instead of picking.
			if seen[h] {
				return fmt.Errorf("hostname %q appears in more than one route", h)
			}
			seen[h] = true
		}
		for _, u := range r.Upstreams {
			if err := validUpstream(u); err != nil {
				return err
			}
		}
	}
	return nil
}

// An upstream is a backend box: `host:port`, where host is a name or an address. The
// port is required — this is not a site address and there is no sensible default to
// guess, so a missing one is a mistake rather than shorthand.
func validUpstream(u string) error {
	const shape = `upstream %q is not host:port — use "10.0.0.5:8080" or "backend.internal:8080"`
	i := strings.LastIndexByte(u, ':')
	if i <= 0 {
		return fmt.Errorf(shape, u)
	}
	port, err := strconv.Atoi(u[i+1:])
	if err != nil || port < 1 || port > 65535 {
		return fmt.Errorf(shape, u)
	}
	host := u[:i]
	// A bracketed IPv6 literal is the one form with colons inside it.
	if strings.HasPrefix(host, "[") && strings.HasSuffix(host, "]") {
		if len(host) <= 2 {
			return fmt.Errorf(shape, u)
		}
		return nil
	}
	if host == "" {
		return fmt.Errorf(shape, u)
	}
	for _, r := range host {
		ok := r == '.' || r == '-' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !ok {
			return fmt.Errorf(shape, u)
		}
	}
	return nil
}

// renderRoutes is pure, like renderCaddyfile: one reverse-proxy site per route, with
// every upstream on the one directive so Caddy balances across them itself.
func renderRoutes(tbl routeTable) string {
	// Caddy rejects a truly empty config; a comment is a valid no-op, and it is what an
	// emptied table should leave behind.
	if len(tbl.Routes) == 0 {
		return "# Managed by steward. This box fronts nothing.\n"
	}
	var b strings.Builder
	b.WriteString("# Managed by steward — routes to other boxes. Edited by `steward route`.\n\n")
	for _, r := range tbl.Routes {
		fmt.Fprintf(&b, "%s {\n\treverse_proxy %s\n}\n\n",
			strings.Join(r.Hostnames, " "), strings.Join(r.Upstreams, " "))
	}
	return b.String()
}

// currentRoutes reports what this box fronts, for `status`. Read off the fragment the
// verb wrote, so it reflects the box rather than anything the caller believes.
func currentRoutes() []string {
	data, err := os.ReadFile(routesFragmentPath())
	if err != nil {
		return nil
	}
	var out []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if host, ok := strings.CutSuffix(line, " {"); ok {
			out = append(out, host)
		}
	}
	return out
}
