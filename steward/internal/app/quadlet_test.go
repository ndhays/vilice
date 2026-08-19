package app

import (
	"strings"
	"testing"
)

func TestOtherColor(t *testing.T) {
	cases := map[string]string{
		"":  colorA, // first deploy goes to a
		"a": colorB,
		"b": colorA,
	}
	for active, want := range cases {
		if got := otherColor(active); got != want {
			t.Errorf("otherColor(%q) = %q, want %q", active, got, want)
		}
	}
}

func TestNames(t *testing.T) {
	if got := containerName("web", "a"); got != "web-a" {
		t.Errorf("containerName = %q", got)
	}
	if got := unitFileName("web", "b"); got != "web-b.container" {
		t.Errorf("unitFileName = %q", got)
	}
	if got := serviceName("web", "a"); got != "web-a.service" {
		t.Errorf("serviceName = %q", got)
	}
}

func TestPickPortAvoidsUsed(t *testing.T) {
	apps := []appState{
		{Name: "web", Ports: map[string]int{"a": portBase, "b": portBase + 1}},
		{Name: "api", Ports: map[string]int{"a": portBase + 2}},
	}
	used := usedPorts(apps)
	if got := pickPort(used); got != portBase+3 {
		t.Errorf("pickPort = %d, want %d", got, portBase+3)
	}
	// Empty state hands out the base port.
	if got := pickPort(usedPorts(nil)); got != portBase {
		t.Errorf("pickPort(empty) = %d, want %d", got, portBase)
	}
	// A zero port (unassigned color) must not be counted as used.
	used2 := usedPorts([]appState{{Name: "x", Ports: map[string]int{"a": 0}}})
	if got := pickPort(used2); got != portBase {
		t.Errorf("pickPort with zero port = %d, want %d", got, portBase)
	}
}

func TestLivePort(t *testing.T) {
	// Blue/green: live = active color's port.
	bg := appState{ActiveColor: "b", Ports: map[string]int{"a": 8800, "b": 8801}, HostPort: 49999}
	if got := bg.livePort(); got != 8801 {
		t.Errorf("livePort (blue/green) = %d, want 8801", got)
	}
	// Legacy: no active color → fall back to HostPort.
	if got := (appState{HostPort: 49999}).livePort(); got != 49999 {
		t.Errorf("livePort (legacy) = %d, want 49999", got)
	}
}

// The dropped capabilities are not a taste. NET_BIND_SERVICE is droppable *because*
// validateState refuses a port below 1024 — the two are one decision, and if the port
// floor ever moves, dropping the capability silently stops being justified and starts
// breaking apps. This is the test that would fail first.
func TestPortFloorIsWhatJustifiesDroppingNetBindService(t *testing.T) {
	base := appState{
		Name:      "web",
		Image:     "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000",
		Health:    "/",
		Hostnames: []string{"app.example.com"},
	}

	for _, port := range []int{1, 80, 443, 1023} {
		st := base
		st.Port = port
		if err := validateState(st); err == nil {
			t.Fatalf("port %d was accepted — a privileged port is reachable, so the unit "+
				"must stop dropping CAP_NET_BIND_SERVICE", port)
		}
	}

	st := base
	st.Port = 1024
	if err := validateState(st); err != nil {
		t.Fatalf("port 1024 should be the floor, not refused: %v", err)
	}
	if !strings.Contains(renderQuadletUnit(st, "a", 8800, true), "CAP_NET_BIND_SERVICE") {
		t.Error("the unit no longer drops CAP_NET_BIND_SERVICE")
	}
}

func TestRenderQuadletUnit(t *testing.T) {
	st := appState{
		Name:        "web",
		Image:       "registry.example/web@sha256:abc0000000000000000000000000000000000000000000000000000000000000",
		Port:        8080,
		Health:      "/up",
		Env:         map[string]string{"RAILS_ENV": "production", "A_FLAG": "with space"},
		Secrets:     []string{"RAILS_MASTER_KEY"},
		SecretFiles: map[string]string{"config": "/etc/zot/config.json"},
		Volumes:     []string{"web-data:/rails/storage"},
	}
	got := renderQuadletUnit(st, "a", 8800, true)

	wantLines := []string{
		"[Container]",
		"Image=registry.example/web@sha256:abc0000000000000000000000000000000000000000000000000000000000000",
		"ContainerName=web-a",
		"PublishPort=127.0.0.1:8800:8080",
		`Environment="PORT=8080"`,
		`Environment="A_FLAG=with space"`, // sorted before RAILS_ENV; value quoted
		`Environment="RAILS_ENV=production"`,
		"Secret=web__RAILS_MASTER_KEY,type=env,target=RAILS_MASTER_KEY",
		"Secret=web__config,type=mount,target=/etc/zot/config.json", // file secret → mount
		"Volume=web-data:/rails/storage",
		// The container's own ceiling. NET_BIND_SERVICE is dropped because `deploy`
		// already refuses a port below 1024 — the capability is provably unused here.
		"NoNewPrivileges=true",
		"DropCapability=CAP_NET_BIND_SERVICE CAP_SETFCAP CAP_SETPCAP CAP_SYS_CHROOT",
		"[Service]",
		"TimeoutStopSec=30",
		"Restart=on-failure",
		"OOMScoreAdjust=100",
		"[Install]",
		"WantedBy=default.target",
	}
	for _, w := range wantLines {
		if !strings.Contains(got, w) {
			t.Errorf("unit missing line %q\n--- got ---\n%s", w, got)
		}
	}

	// Env keys are emitted in sorted order (deterministic units).
	if strings.Index(got, "A_FLAG=") > strings.Index(got, "RAILS_ENV=") {
		t.Error("env keys not sorted")
	}
	// No edit-this footgun: the generated banner is present.
	if !strings.HasPrefix(got, "# Managed by steward.") {
		t.Error("missing generated-file banner")
	}

	// enabled=false drops [Install] so the unit won't start at boot (how stop persists).
	disabled := renderQuadletUnit(st, "a", 8800, false)
	if strings.Contains(disabled, "[Install]") || strings.Contains(disabled, "WantedBy") {
		t.Errorf("disabled unit must omit [Install]/WantedBy\n%s", disabled)
	}
}

func TestQuoteEnv(t *testing.T) {
	cases := map[[2]string]string{
		{"K", "v"}:   `"K=v"`,
		{"K", "a b"}: `"K=a b"`,
		{"K", `a"b`}: `"K=a\"b"`,
		{"K", `a\b`}: `"K=a\\b"`,
	}
	for in, want := range cases {
		if got := quoteEnv(in[0], in[1]); got != want {
			t.Errorf("quoteEnv(%q,%q) = %q, want %q", in[0], in[1], got, want)
		}
	}
}
