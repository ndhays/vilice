package app

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A process is the app's own image running a different command — a worker, a clock. The
// point is that it *cannot* drift from the web process, so most of these assert things
// the two share rather than things the process has. See process.go.

func processApp() appState {
	return appState{
		Name: "web", Image: "img@sha256:" + strings.Repeat("a", 64),
		Hostnames: []string{"app.example.com"}, Port: 8080, Health: "/up",
		Env:       map[string]string{"RAILS_ENV": "production"},
		Secrets:   []string{"SECRET_KEY_BASE"},
		Volumes:   []string{"web-data:/rails/storage"},
		Processes: []Process{{Name: "worker", Command: []string{"bin/jobs"}}},
	}
}

func TestRenderProcessUnit(t *testing.T) {
	st := processApp()
	got := renderProcessUnit(st, st.Processes[0], "a", true)

	for _, want := range []string{
		"ContainerName=web-worker-a",
		`Exec="bin/jobs"`,
		// Inherited, every one of them — that is the whole design.
		"Image=img@sha256:" + strings.Repeat("a", 64),
		`Environment="RAILS_ENV=production"`,
		"Secret=web__SECRET_KEY_BASE,type=env,target=SECRET_KEY_BASE",
		"Volume=web-data:/rails/storage",
		"NoNewPrivileges=true",
		"WantedBy=default.target",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("process unit missing %q\n--- got ---\n%s", want, got)
		}
	}
	// Nothing reaches a worker, so it publishes nothing and Caddy is never told about it.
	if strings.Contains(got, "PublishPort") {
		t.Error("a process published a port")
	}
}

// An argument with a space is one argument. systemd splits Exec= on whitespace, so this
// is the same trap quoteEnv exists for, one directive over.
func TestProcessCommandSurvivesASpace(t *testing.T) {
	st := processApp()
	st.Processes[0].Command = []string{"bin/rails", "runner", "puts 1"}

	if got := renderProcessUnit(st, st.Processes[0], "a", true); !strings.Contains(got, `Exec="bin/rails" "runner" "puts 1"`) {
		t.Errorf("argv was not quoted per element:\n%s", got)
	}
}

// The property the whole feature exists for: web and worker cannot be at different
// digests, because there is only one digest.
func TestAProcessCannotDriftFromItsApp(t *testing.T) {
	st := processApp()
	web := renderQuadletUnit(st, "a", 8800, true)
	worker := renderProcessUnit(st, st.Processes[0], "a", true)

	if !strings.Contains(web, st.Image) || !strings.Contains(worker, st.Image) {
		t.Fatal("the two units do not name the same image")
	}
	// And changing the worker's command changes the spec, so it is a deploy.
	other := processApp()
	other.Processes[0].Command = []string{"bin/other"}
	if appDigest(st) == appDigest(other) {
		t.Error("a process command is not part of the spec digest")
	}
	none := processApp()
	none.Processes = nil
	if appDigest(none) == appDigest(st) {
		t.Error("declaring a process did not change the spec")
	}
}

// A colour is the whole app: both units are written together and torn down together, so
// there is no state where one is up and the other is not.
func TestAColourWritesEveryProcessUnit(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("VILICE_QUADLET_DIR", dir)
	st := processApp()

	if err := writeUnit(st, "a", 8800, true); err != nil {
		t.Fatalf("writeUnit: %v", err)
	}
	for _, name := range []string{"web-a.container", "web-worker-a.container"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("a colour did not write %s: %v", name, err)
		}
	}
}

func TestValidProcesses(t *testing.T) {
	if err := validateState(processApp()); err != nil {
		t.Fatalf("a plain process was refused: %v", err)
	}

	cases := map[string]func(*appState){
		"with no command":       func(s *appState) { s.Processes[0].Command = nil },
		"named for its own app": func(s *appState) { s.Processes[0].Name = "web" },
		"with a bad name":       func(s *appState) { s.Processes[0].Name = "my worker" },
		"with a shell in argv":  func(s *appState) { s.Processes[0].Command = []string{"bin/jobs\nExec=evil"} },
	}
	for label, break_ := range cases {
		st := processApp()
		break_(&st)
		if err := validateState(st); err == nil {
			t.Errorf("a process %s was accepted", label)
		}
	}

	dup := processApp()
	dup.Processes = append(dup.Processes, dup.Processes[0])
	if err := validateState(dup); err == nil {
		t.Error("the same process declared twice was accepted")
	}
}

// Colours, processes and accessories all mint container names from the app's, and two
// landing on one name would have each silently overwrite the other's unit file.
func TestContainerNamesCannotCollide(t *testing.T) {
	// An accessory named for a process's colour-suffixed container.
	st := processApp()
	st.Accessories = []Accessory{{
		Name:  "worker-a",
		Image: "p@sha256:" + strings.Repeat("b", 64),
	}}
	if err := validateState(st); err == nil {
		t.Error("an accessory and a process colour claimed the same container name")
	}

	// And the ordinary case still passes.
	ok := processApp()
	ok.Accessories = []Accessory{{Name: "db", Image: "p@sha256:" + strings.Repeat("b", 64)}}
	if err := validateState(ok); err != nil {
		t.Errorf("distinct names were refused: %v", err)
	}
}

// A process joins the app's network for the same reason the web container does: a worker
// that cannot reach the database is not a worker.
func TestAProcessJoinsTheAccessoryNetwork(t *testing.T) {
	st := processApp()
	st.Accessories = []Accessory{{Name: "db", Image: "p@sha256:" + strings.Repeat("b", 64)}}

	if got := renderProcessUnit(st, st.Processes[0], "a", true); !strings.Contains(got, "Network=vilice-web") {
		t.Errorf("a process did not join its app's network:\n%s", got)
	}
	// And with no accessory there is no network to join.
	if got := renderProcessUnit(processApp(), st.Processes[0], "a", true); strings.Contains(got, "Network=") {
		t.Error("a process joined a network that does not exist")
	}
}
