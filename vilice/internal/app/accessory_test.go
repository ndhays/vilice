package app

import (
	"strings"
	"testing"
)

// Accessories are subordinate by construction: no hostname, never routed, on a network
// only their own app joins, created and destroyed with it. See accessory.go and
// decisions/accessories-belong-to-one-app.md.

func accessoryApp() appState {
	return appState{
		Name: "web", Image: "img@sha256:" + strings.Repeat("a", 64),
		Hostnames: []string{"app.example.com"}, Port: 8080, Health: "/up",
		Accessories: []Accessory{{
			Name:    "db",
			Image:   "docker.io/library/postgres@sha256:" + strings.Repeat("b", 64),
			Env:     map[string]string{"POSTGRES_DB": "app", "A_FIRST": "1"},
			Secrets: []string{"POSTGRES_PASSWORD"},
			Volumes: []string{"web-db:/var/lib/postgresql/data"},
		}},
	}
}

// The unit is the whole isolation story, so it is asserted line by line.
func TestRenderAccessoryUnit(t *testing.T) {
	got := renderAccessoryUnit("web", accessoryApp().Accessories[0])

	for _, want := range []string{
		"ContainerName=web-db",
		"Network=vilice-web",
		// The app says `db:5432`; the container is called `web-db`. The alias is what
		// makes the spec's name the name that resolves.
		"NetworkAlias=db",
		`Environment="A_FIRST=1"`, // sorted
		`Environment="POSTGRES_DB=app"`,
		"Secret=web-db__POSTGRES_PASSWORD,type=env,target=POSTGRES_PASSWORD",
		"Volume=web-db:/var/lib/postgresql/data",
		"NoNewPrivileges=true",
		"DropCapability=CAP_NET_BIND_SERVICE",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("accessory unit missing %q\n--- got ---\n%s", want, got)
		}
	}

	// **No published port.** This is the isolation: an accessory is reachable on its
	// app's network and nowhere else — not from another app, not from the host, not from
	// outside. A PublishPort here would quietly undo the whole design.
	if strings.Contains(got, "PublishPort") {
		t.Error("an accessory published a port — it is reachable off its network")
	}
	// Nothing routes to it, so it has no hostname and no health path to probe.
	if strings.Contains(got, "Hostname") || strings.Contains(got, "health") {
		t.Error("an accessory unit carried routing or health config")
	}
}

// The app joins its accessories' network — and only then, because a Network= naming one
// that was never created would fail the unit at start.
func TestAppJoinsItsAccessoryNetworkOnlyWhenItHasOne(t *testing.T) {
	with := renderQuadletUnit(accessoryApp(), "a", 8800, true)
	if !strings.Contains(with, "Network=vilice-web") {
		t.Error("an app with accessories does not join their network")
	}

	plain := accessoryApp()
	plain.Accessories = nil
	if strings.Contains(renderQuadletUnit(plain, "a", 8800, true), "Network=") {
		t.Error("an app with no accessories joined a network that does not exist")
	}
}

// Both colors share the one network, so a flip does not disturb what the database sees.
func TestBothColorsShareOneNetwork(t *testing.T) {
	st := accessoryApp()
	a := renderQuadletUnit(st, "a", 8800, true)
	b := renderQuadletUnit(st, "b", 8801, true)

	if !strings.Contains(a, "Network=vilice-web") || !strings.Contains(b, "Network=vilice-web") {
		t.Fatal("the colors are not on the same network")
	}
}

// An accessory is part of what the app *is*: changing the database's image is a change
// to the deploy, not a detail beside it.
func TestAccessoriesAreInsideTheSpecDigest(t *testing.T) {
	pg16 := accessoryApp()
	pg17 := accessoryApp()
	pg17.Accessories[0].Image = "docker.io/library/postgres@sha256:" + strings.Repeat("c", 64)

	if appDigest(pg16) == appDigest(pg17) {
		t.Error("the accessory's image is not part of the spec digest")
	}

	none := accessoryApp()
	none.Accessories = nil
	if appDigest(none) == appDigest(pg16) {
		t.Error("declaring an accessory did not change the spec")
	}
}

func TestValidAccessories(t *testing.T) {
	ok := accessoryApp()
	if err := validateState(ok); err != nil {
		t.Fatalf("a plain accessory was refused: %v", err)
	}

	cases := map[string]func(*appState){
		// `a` and `b` are the app's own color suffixes, so `web-a.container` would be
		// written twice — once for a color and once for an accessory.
		"named for a deploy color":   func(s *appState) { s.Accessories[0].Name = "a" },
		"named for its own app":      func(s *appState) { s.Accessories[0].Name = "web" },
		"name outside the charset":   func(s *appState) { s.Accessories[0].Name = "my db" },
		"image is not digest-pinned": func(s *appState) { s.Accessories[0].Image = "postgres:16" },
		"no image at all":            func(s *appState) { s.Accessories[0].Image = "" },
		"volume escaping the root":   func(s *appState) { s.Accessories[0].Volumes = []string{"/etc:/etc"} },
		"invalid secret name":        func(s *appState) { s.Accessories[0].Secrets = []string{"not a name"} },
	}
	for name, break_ := range cases {
		st := accessoryApp()
		break_(&st)
		if err := validateState(st); err == nil {
			t.Errorf("an accessory %s was accepted", name)
		}
	}

	dup := accessoryApp()
	dup.Accessories = append(dup.Accessories, dup.Accessories[0])
	if err := validateState(dup); err == nil {
		t.Error("the same accessory declared twice was accepted")
	}
}

// One envelope carries everything the app needs, the database password included — and
// the store namespaces it by container, so two POSTGRES_PASSWORDs cannot collide in a
// namespace that is global.
func TestAccessorySecretsAreDeclaredOnceAndStoredApart(t *testing.T) {
	st := accessoryApp()
	st.Secrets = []string{"RAILS_MASTER_KEY"}

	names := declaredSecretNames(st)
	for _, want := range []string{"RAILS_MASTER_KEY", "POSTGRES_PASSWORD"} {
		if !contains(names, want) {
			t.Errorf("declaredSecretNames missing %q — its value would never be asked for", want)
		}
	}
	if secretRef("web", "POSTGRES_PASSWORD") == accessorySecretRef("web", "db", "POSTGRES_PASSWORD") {
		t.Error("an accessory's secret shares the app's namespace")
	}
}

func contains(xs []string, want string) bool {
	for _, x := range xs {
		if x == want {
			return true
		}
	}
	return false
}
