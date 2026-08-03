package app

// Split out of the core when the core/pack line was drawn: these assert
// properties of what this pack renders and writes to the box, so they belong
// with the code that renders it. The assertions are unchanged.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Listing the destinations rather than the two known routes is the point: a third route
// that lands on any of these fails here.
func TestOperateCannotReachTheFilesThatGrantPrivilege(t *testing.T) {
	privileged := []string{
		"/home/steward/.ssh",                       // the rights ledger: writing it is an ssh grant
		"/home/steward/.ssh/authorized_keys",       //
		"/home/steward/.config/containers/systemd", // quadlet units: arbitrary containers at boot
		"/home/steward/.config/containers",         // the registry auth file
		"/var/lib/steward",                         // the record and every app's state
		"/var/lib/steward/secrets",                 // the restic password
		"/etc/caddy",                               // routing for every app on the box
		"/etc/sudoers.d",                           // the OS-update grant
		"/etc",
		"/root",
		"/",
	}
	for _, p := range privileged {
		for _, spec := range []string{p + ":/x:rw", p + ":/x:ro", p + "/:/x", "/srv/../" + p + ":/x"} {
			if err := validVolume(spec); err == nil {
				t.Errorf("an operate key could bind-mount %q", spec)
			}
		}
	}
}

// A spec that never went through deploy — one read back off disk, say — still cannot
// inject directives into a unit. The render boundary checks rather than trusting that
// whatever is on disk was checked on the way in.
func TestWriteUnitRefusesAnUnrenderableSpec(t *testing.T) {
	t.Setenv("STEWARD_QUADLET_DIR", t.TempDir())
	hostile := []appState{
		{Name: "web", Image: "img@sha256:abc", Hostnames: []string{"a.example.com"}, Port: 8080,
			Volumes: []string{"data:/d\nPodmanArgs=--privileged"}},
		{Name: "web", Image: "img@sha256:abc\nAddCapability=CAP_SYS_ADMIN", Hostnames: []string{"a.example.com"}, Port: 8080},
		{Name: "web", Image: "img@sha256:abc", Hostnames: []string{"a.example.com"}, Port: 8080,
			Env: map[string]string{"K": "v\nUser=root"}},
	}
	for _, st := range hostile {
		if err := writeUnit(st, "a", 8800, true); err == nil {
			t.Errorf("writeUnit accepted a spec it should have refused: %+v", st)
		}
	}
}

// The consequence that matters is upgrade. An app deployed before the bind-root rule
// existed keeps running, keeps its route, and keeps rendering its unit — it only meets
// the new rule when someone tries to deploy it again, which is a loud error naming the
// problem rather than a route silently disappearing.
func TestPolicyIsCheckedOnTheWayInOnly(t *testing.T) {
	legacy := appState{
		Name: "web", Image: "img@sha256:abc", Hostnames: []string{"app.example.com"},
		Port: 8080, Health: "/",
		Volumes: []string{"/data/web:/data"}, // outside the bind root — predates the rule
	}

	// The door refuses it: it cannot be newly deployed or restored.
	if err := validateState(legacy); err == nil {
		t.Error("the deploy door accepted a bind mount outside the data root")
	}
	// The box keeps working: it renders, it persists, it routes.
	if err := validateRenderable(legacy); err != nil {
		t.Errorf("an existing app stopped being renderable: %v", err)
	}
	t.Setenv("STEWARD_QUADLET_DIR", t.TempDir())
	if err := writeUnit(legacy, "a", 8800, true); err != nil {
		t.Errorf("an existing app's unit stopped being writable: %v", err)
	}
	t.Setenv("STEWARD_APPS_DIR", t.TempDir())
	if err := saveApp(legacy); err != nil {
		t.Errorf("an existing app could no longer be re-persisted (rollback would fail): %v", err)
	}
	if out := renderCaddyfile([]appState{legacy}); !strings.Contains(out, "app.example.com") {
		t.Errorf("an existing app lost its route:\n%s", out)
	}
}

// The other render boundary. App state reaches the Caddy fragment straight off disk
// (loadApp deliberately doesn't validate, so an app with a stale spec stays visible in
// `status` rather than silently vanishing), so the check happens on the way into the
// fragment — and refusing leaves the previous routing untouched rather than dropping a
// route or writing a site block nobody declared.
func TestRefreshCaddyRefusesAnInvalidSpecOnDisk(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_APPS_DIR", filepath.Join(dir, "apps"))
	fragment := filepath.Join(dir, "apps.caddy")
	t.Setenv("STEWARD_CADDY_FRAGMENT", fragment)
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		t.Fatal(err)
	}

	hostile := `{"name":"web","image":"img@sha256:abc","port":8080,
	  "hostnames":["evil.com\n}\n:9999 {\n\troot * /\n\tfile_server browse\n}\n#"],
	  "active_color":"a","ports":{"a":8800}}`
	if err := os.WriteFile(appPath("web"), []byte(hostile), 0o600); err != nil {
		t.Fatal(err)
	}

	err := refreshCaddy()
	if err == nil {
		t.Fatal("refreshCaddy accepted a spec that restructures the fragment")
	}
	if _, statErr := os.Stat(fragment); statErr == nil {
		b, _ := os.ReadFile(fragment)
		t.Errorf("the fragment was written anyway:\n%s", b)
	}
}

// Defense in depth: the functions that turn a name into a path refuse a bad name even
// when called directly, so a future caller that skips dispatch still cannot escape the
// apps dir. This is the finding that was live — removeApp("../victim") deleted a file
// outside its directory.
func TestStateFunctionsRefuseTraversal(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_APPS_DIR", filepath.Join(dir, "apps"))
	t.Setenv("STEWARD_QUADLET_DIR", filepath.Join(dir, "quadlet"))
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		t.Fatal(err)
	}

	victim := filepath.Join(dir, "victim.json")
	if err := os.WriteFile(victim, []byte(`{"name":"victim"}`), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := removeApp("../victim"); err == nil {
		t.Error("removeApp accepted a traversal name")
	}
	if _, err := os.Stat(victim); err != nil {
		t.Errorf("removeApp deleted a file outside the apps dir: %v", err)
	}
	if _, ok := loadApp("../victim"); ok {
		t.Error("loadApp read a file outside the apps dir")
	}
	if err := saveApp(appState{Name: "../escapee"}); err == nil {
		t.Error("saveApp accepted a traversal name")
	}
	if err := writeUnit(appState{Name: "../escapee"}, "a", 8800, true); err == nil {
		t.Error("writeUnit accepted a traversal name")
	}
	if err := removeUnit("../escapee", "a"); err == nil {
		t.Error("removeUnit accepted a traversal name")
	}
}
