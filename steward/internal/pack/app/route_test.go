package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"steward/internal/core"
)

func TestRenderRoutesOneUpstream(t *testing.T) {
	got := renderRoutes(routeTable{Routes: []route{
		{Hostnames: []string{"app.example.com"}, Upstreams: []string{"10.0.0.5:8080"}},
	}})
	if !strings.Contains(got, "app.example.com {") {
		t.Errorf("missing site address:\n%s", got)
	}
	if !strings.Contains(got, "reverse_proxy 10.0.0.5:8080") {
		t.Errorf("missing upstream:\n%s", got)
	}
}

// Several upstreams share one directive — that is what makes Caddy balance across
// them rather than treating each as its own site.
func TestRenderRoutesBalancesAcrossUpstreams(t *testing.T) {
	got := renderRoutes(routeTable{Routes: []route{
		{Hostnames: []string{"app.example.com", "www.example.com"},
			Upstreams: []string{"10.0.0.5:8080", "10.0.0.6:8080"}},
	}})
	if !strings.Contains(got, "app.example.com www.example.com {") {
		t.Errorf("hostnames should share one site address:\n%s", got)
	}
	if !strings.Contains(got, "reverse_proxy 10.0.0.5:8080 10.0.0.6:8080") {
		t.Errorf("upstreams should share one directive:\n%s", got)
	}
	if strings.Count(got, "reverse_proxy") != 1 {
		t.Errorf("expected exactly one directive:\n%s", got)
	}
}

// Caddy refuses a truly empty config, and "front nothing" has to be expressible —
// it is how a box is taken out of service.
func TestRenderRoutesEmptyIsAValidNoOp(t *testing.T) {
	got := renderRoutes(routeTable{})
	if strings.TrimSpace(got) == "" {
		t.Error("an emptied table must still render a valid config, not nothing")
	}
	if !strings.HasPrefix(strings.TrimSpace(got), "#") {
		t.Errorf("expected a comment no-op, got:\n%s", got)
	}
}

func TestValidateTableAcceptsEmpty(t *testing.T) {
	if err := validateTable(routeTable{}); err != nil {
		t.Errorf("an empty table means 'front nothing' and must be allowed: %v", err)
	}
}

func TestValidateTableRejectsRouteToNowhere(t *testing.T) {
	err := validateTable(routeTable{Routes: []route{
		{Hostnames: []string{"app.example.com"}},
	}})
	if err == nil || !strings.Contains(err.Error(), "no upstreams") {
		t.Errorf("a hostname with no upstreams should be refused, got %v", err)
	}
}

func TestValidateTableRejectsHostnameInTwoRoutes(t *testing.T) {
	err := validateTable(routeTable{Routes: []route{
		{Hostnames: []string{"app.example.com"}, Upstreams: []string{"10.0.0.5:8080"}},
		{Hostnames: []string{"app.example.com"}, Upstreams: []string{"10.0.0.6:8080"}},
	}})
	if err == nil || !strings.Contains(err.Error(), "more than one route") {
		t.Errorf("an ambiguous hostname should be refused rather than silently resolved, got %v", err)
	}
}

func TestValidUpstream(t *testing.T) {
	ok := []string{"10.0.0.5:8080", "backend.internal:80", "b-1.example.com:65535", "[::1]:8080"}
	for _, u := range ok {
		if err := validUpstream(u); err != nil {
			t.Errorf("validUpstream(%q) = %v, want nil", u, err)
		}
	}
	// A bare host is refused: there is no port to guess, and guessing is how traffic
	// silently goes somewhere nobody chose.
	bad := []string{"10.0.0.5", "backend.internal", "", ":8080", "host:0", "host:70000",
		"host:notaport", "http://host:80"}
	for _, u := range bad {
		if err := validUpstream(u); err == nil {
			t.Errorf("validUpstream(%q) = nil, want an error", u)
		}
	}
}

// The whole point of the verb: an upstream that is not this box. Guards against the
// route fragment ever collapsing back into the loopback-only shape apps use.
func TestRoutesReachOtherBoxes(t *testing.T) {
	got := renderRoutes(routeTable{Routes: []route{
		{Hostnames: []string{"app.example.com"}, Upstreams: []string{"10.0.0.5:8080"}},
	}})
	if strings.Contains(got, "127.0.0.1") {
		t.Errorf("a route's upstream is another box, never loopback:\n%s", got)
	}
}

// The two fragments are separate files in one imported directory, so writing routes
// cannot disturb app routes and vice versa.
func TestRoutesFragmentIsSeparateFromApps(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_CADDY_ROUTES", filepath.Join(dir, "routes.caddy"))
	t.Setenv("STEWARD_CADDY_FRAGMENT", filepath.Join(dir, "apps.caddy"))

	if routesFragmentPath() == caddyFragmentPath() {
		t.Fatal("routes and apps must not share a file — one would clobber the other")
	}
	if filepath.Dir(routesFragmentPath()) != filepath.Dir(caddyFragmentPath()) {
		t.Error("both fragments must sit in the directory the base Caddyfile imports")
	}
}

// currentRoutes reads what was written, so `status` reports the box rather than
// anything the caller believed it asked for.
func TestCurrentRoutesReadsTheFragment(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "routes.caddy")
	t.Setenv("STEWARD_CADDY_ROUTES", path)

	tbl := routeTable{Routes: []route{
		{Hostnames: []string{"a.example.com"}, Upstreams: []string{"10.0.0.5:8080"}},
		{Hostnames: []string{"b.example.com", "c.example.com"}, Upstreams: []string{"10.0.0.6:8080"}},
	}}
	if err := os.WriteFile(path, []byte(renderRoutes(tbl)), 0o644); err != nil {
		t.Fatal(err)
	}

	got := currentRoutes()
	want := []string{"a.example.com", "b.example.com c.example.com"}
	if len(got) != len(want) {
		t.Fatalf("currentRoutes() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("currentRoutes()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestCurrentRoutesEmptyWhenNothingWritten(t *testing.T) {
	t.Setenv("STEWARD_CADDY_ROUTES", filepath.Join(t.TempDir(), "absent.caddy"))
	if got := currentRoutes(); len(got) != 0 {
		t.Errorf("currentRoutes() = %v, want empty when the box fronts nothing", got)
	}
}

// The whole path, stdin to fragment: what a scoped SSH call actually does. Driven
// through routeCmd rather than the pure renderer, so the JSON shape the console sends
// is the thing under test.
func TestRouteCmdWritesFragmentFromStdin(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_CADDY_ROUTES", filepath.Join(dir, "routes.caddy"))
	// Point the reload at a config that isn't there, so a developer machine with Caddy
	// installed doesn't get its real edge reloaded by running the tests. The reload is
	// expected to fail here; the write under test happens before it.
	t.Setenv("STEWARD_CADDYFILE", filepath.Join(dir, "absent-Caddyfile"))

	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		_, _ = w.WriteString(`{"routes":[{"hostnames":["app.example.com"],` +
			`"upstreams":["10.0.0.5:8080","10.0.0.6:8080"]}]}`)
		_ = w.Close()
	}()
	saved := os.Stdin
	os.Stdin = r
	defer func() { os.Stdin = saved }()

	res := routeCmd(nil)

	// The fragment is written before the reload is attempted, so it lands whether or
	// not a Caddy is present in the test environment.
	got, readErr := os.ReadFile(routesFragmentPath())
	if readErr != nil {
		t.Fatalf("no fragment written (result %+v): %v", res, readErr)
	}
	if !strings.Contains(string(got), "reverse_proxy 10.0.0.5:8080 10.0.0.6:8080") {
		t.Errorf("fragment does not carry the upstreams:\n%s", got)
	}
	if res.Code != "ok" && res.Code != "reload_failed" {
		t.Errorf("unexpected result code %q (%s)", res.Code, res.Message)
	}
}

// A malformed table must leave the box serving what it was serving. Losing every route
// to a bad request is worse than refusing the request.
func TestRouteCmdRefusalLeavesThePreviousTable(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "routes.caddy")
	t.Setenv("STEWARD_CADDY_ROUTES", path)

	good := renderRoutes(routeTable{Routes: []route{
		{Hostnames: []string{"kept.example.com"}, Upstreams: []string{"10.0.0.5:8080"}},
	}})
	if err := os.WriteFile(path, []byte(good), 0o644); err != nil {
		t.Fatal(err)
	}

	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		// A hostname routed nowhere — refused by validateTable, before any write.
		_, _ = w.WriteString(`{"routes":[{"hostnames":["new.example.com"],"upstreams":[]}]}`)
		_ = w.Close()
	}()
	saved := os.Stdin
	os.Stdin = r
	defer func() { os.Stdin = saved }()

	if res := routeCmd(nil); res.Code != "bad_args" {
		t.Errorf("expected bad_args, got %q (%s)", res.Code, res.Message)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != good {
		t.Errorf("a refused table must not disturb the fragment:\n%s", after)
	}
}

// A balancer has no container runtime, on purpose. `deploy` says so rather than letting
// the operator meet "podman: not found" and guess why.
func TestDeployRefusedOnABalancer(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	if err := core.SetRole(core.RoleBalancer); err != nil {
		t.Fatal(err)
	}
	res := deployCmd([]string{"web", "--image", "ghcr.io/x/y@sha256:abc"})
	if res.Code != "wrong_role" {
		t.Fatalf("got %q (%s), want wrong_role", res.Code, res.Message)
	}
	if !strings.Contains(res.Message, "balancer") {
		t.Errorf("the refusal should name the role: %q", res.Message)
	}
}

// A host deploys normally — the guard must not fire on the role that runs apps, nor on
// a box that was never prepared.
func TestDeployNotRefusedOnAHostOrUnprepared(t *testing.T) {
	for _, setup := range []string{core.RoleHost, ""} {
		t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
		if setup != "" {
			if err := core.SetRole(setup); err != nil {
				t.Fatal(err)
			}
		}
		if res := deployCmd([]string{"web", "--image", "ghcr.io/x/y@sha256:abc"}); res.Code == "wrong_role" {
			t.Errorf("role %q should not be refused by the role guard", setup)
		}
	}
}
