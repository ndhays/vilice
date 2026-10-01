package app

// Split out of the core when the core/app line was drawn: these assert
// properties of what this layer renders and writes to the box, so they belong
// with the code that renders it. The assertions are unchanged.

import (
	"strings"
	"testing"

	"vilice/internal/core"
)

// The site address is the attacker-controlled part of a Caddy block. The property is
// not "reject everything ugly" — a hostname may contain a quote or a dollar sign and
// still be a harmless (if useless) address, because nothing here reaches a shell. The
// property is that whatever validation admits renders as exactly one site.
func TestCaddyfileShapeHoldsForValidatedHostnames(t *testing.T) {
	withHostname := func(h string) appState {
		return appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Port: 8080, Health: "/",
			Hostnames: []string{h}, ActiveColor: "a", Ports: map[string]int{"a": 8800},
		}
	}

	// Real site addresses render as exactly one site.
	for _, h := range []string{
		"app.example.com", "http://app.example.com", "https://app.example.com",
		"*.example.com", "example.com:8443", "localhost", "a-b.c.example.com",
	} {
		st := withHostname(h)
		if err := validateState(st); err != nil {
			t.Errorf("rejected a real site address %q: %v", h, err)
			continue
		}
		assertCaddyShape(t, renderCaddyfile([]appState{st}), 1)
	}

	// Nothing in the hostile corpus gets as far as the renderer. "#" is the one a
	// block-list of bad characters missed: it comments out the site's opening line and
	// breaks routing for every app sharing the fragment.
	for _, h := range append([]string{"#", "#app.example.com", ":80 {", "example.com {"}, hostileStrings...) {
		if err := validateState(withHostname(h)); err == nil {
			t.Errorf("validation admitted hostname %q — it can restructure the Caddy fragment", h)
		}
	}
}

func FuzzCaddyfileShape(f *testing.F) {
	for _, s := range hostileStrings {
		f.Add(s)
	}
	f.Add("app.example.com")
	f.Fuzz(func(t *testing.T, hostname string) {
		st := appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Port: 8080, Health: "/",
			Hostnames: []string{hostname}, ActiveColor: "a", Ports: map[string]int{"a": 8800},
		}
		if validateState(st) != nil {
			return
		}
		assertCaddyShape(t, renderCaddyfile([]appState{st}), 1)
	})
}

func TestQuadletRejectsHostileVolumesAndImages(t *testing.T) {
	base := func() appState {
		return appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Port: 8080, Health: "/",
			Hostnames: []string{"app.example.com"},
		}
	}
	for _, s := range hostileStrings {
		vol := base()
		vol.Volumes = []string{s}
		if err := validateState(vol); err == nil {
			t.Errorf("validation admitted volume %q", s)
		}
		img := base()
		img.Image = s
		if err := validateState(img); err == nil {
			t.Errorf("validation admitted image %q", s)
		}
		env := base()
		env.Env = map[string]string{"KEY": s}
		if err := validateState(env); err == nil && core.HasControlChar(s) {
			t.Errorf("validation admitted env value %q", s)
		}
	}
}

// The escalation that was live: a bind mount of host root gives an operate key write
// access to ~_vilice/.ssh/authorized_keys, and with it an ssh grant.
func TestBindMountsAreConfinedToTheDataRoot(t *testing.T) {
	escapes := []string{
		"/:/host:rw",
		"/etc:/etc",
		"/home/_vilice/.ssh:/keys:rw",
		"/var/lib/vilice:/state:rw",
		"/srv/../etc:/etc",
		"/srv/../../root:/root",
	}
	for _, v := range escapes {
		if err := validVolume(v); err == nil {
			t.Errorf("volume %q escaped the data root", v)
		}
	}
	for _, v := range []string{"/srv/app-data:/data", "/srv:/data:ro", "app-data:/data", "data_1:/x"} {
		if err := validVolume(v); err != nil {
			t.Errorf("volume %q should be allowed: %v", v, err)
		}
	}
}

func FuzzQuadletUnitShape(f *testing.F) {
	for _, s := range hostileStrings {
		f.Add(s, "v")
	}
	f.Add("/srv/data:/data", "value")
	f.Fuzz(func(t *testing.T, volume, envValue string) {
		st := appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Port: 8080, Health: "/",
			Hostnames: []string{"app.example.com"},
			Volumes:   []string{volume},
			Env:       map[string]string{"KEY": envValue},
		}
		if validateState(st) != nil {
			return
		}
		assertQuadletShape(t, renderQuadletUnit(st, "a", 8800, true))
	})
}

// The accessory unit is a second line-oriented file built from declared values, so it
// owes the same guarantee: no value may end its own line and write the next directive.
// Without this, `PublishPort=…` smuggled through an env value would quietly undo the one
// thing that keeps an accessory reachable only by its app.
func FuzzAccessoryUnitShape(f *testing.F) {
	for _, s := range hostileStrings {
		f.Add(s, "v")
	}
	f.Add("/srv/data:/data", "value")
	f.Fuzz(func(t *testing.T, volume, envValue string) {
		st := appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000",
			Port: 8080, Health: "/", Hostnames: []string{"app.example.com"},
			Accessories: []Accessory{{
				Name:    "db",
				Image:   "img@sha256:def0000000000000000000000000000000000000000000000000000000000000",
				Volumes: []string{volume},
				Env:     map[string]string{"KEY": envValue},
			}},
		}
		if validateState(st) != nil {
			return
		}
		assertQuadletShape(t, renderAccessoryUnit(st.Name, st.Accessories[0]))
	})
}

// The third line-oriented file built from declared values, and the one with a command in
// it — so it owes the same guarantee twice over: neither a volume nor an argv element may
// end its own line and write the next directive.
func FuzzProcessUnitShape(f *testing.F) {
	for _, s := range hostileStrings {
		f.Add(s, "v")
	}
	f.Add("/srv/data:/data", "bin/jobs")
	f.Fuzz(func(t *testing.T, volume, arg string) {
		st := appState{
			Name: "web", Image: "img@sha256:abc0000000000000000000000000000000000000000000000000000000000000",
			Port: 8080, Health: "/", Hostnames: []string{"app.example.com"},
			Volumes:   []string{volume},
			Processes: []Process{{Name: "worker", Command: []string{"bin/jobs", arg}}},
		}
		if validateState(st) != nil {
			return
		}
		assertQuadletShape(t, renderProcessUnit(st, st.Processes[0], "a", true))
	})
}

// hostileStrings is the shared corpus: things that end a line, open a block, or
// terminate a string, plus the escapes people reach for to smuggle them.
var hostileStrings = []string{
	"\n",
	"\r\n",
	"\r",
	"x\nInjected=1",
	"x\n}\n:9999 {\n\trespond \"pwned\"\n}\n#",
	"x\nPodmanArgs=--privileged",
	"x\nAddCapability=CAP_SYS_ADMIN",
	"x\nUser=root",
	"x\nVolume=/:/host:rw",
	"x\x00y",
	"x\ty",
	"x\vy",
	"x\fy",
	"x\x7fy",
	"a b",
	"{",
	"}",
	"} {",
	`"`,
	`\`,
	`\n`,
	"$(id)",
	"`id`",
	"../../etc/passwd",
	"",
}

// assertCaddyShape checks the fragment is exactly `apps` sites, each one an address
// line, a reverse_proxy, and a close — nothing else.
func assertCaddyShape(t *testing.T, out string, apps int) {
	t.Helper()
	opens, closes, proxies := 0, 0, 0
	for _, ln := range strings.Split(out, "\n") {
		trimmed := strings.TrimSpace(ln)
		switch {
		case trimmed == "" || strings.HasPrefix(trimmed, "#"):
		case trimmed == "}":
			closes++
		case strings.HasPrefix(trimmed, "reverse_proxy "):
			proxies++
		case strings.HasSuffix(trimmed, "{"):
			opens++
		default:
			t.Fatalf("unexpected line in the Caddy fragment: %q\nfull output:\n%s", ln, out)
		}
	}
	if opens != apps || closes != apps || proxies != apps {
		t.Fatalf("want %d sites, got %d open / %d close / %d reverse_proxy\n%s",
			apps, opens, closes, proxies, out)
	}
}

// assertQuadletShape checks every line is a comment, a blank, a known section, or a
// Key=value whose key the renderer is allowed to emit.
func assertQuadletShape(t *testing.T, out string) {
	t.Helper()
	sections := map[string]bool{"[Unit]": true, "[Container]": true, "[Service]": true, "[Install]": true}
	volumes := 0
	for _, ln := range strings.Split(out, "\n") {
		switch {
		case ln == "" || strings.HasPrefix(ln, "#"):
			continue
		case sections[ln]:
			continue
		}
		key, _, found := strings.Cut(ln, "=")
		if !found || !quadletDirectives[key] {
			t.Fatalf("unexpected directive in the unit: %q\nfull unit:\n%s", ln, out)
		}
		if key == "Volume" {
			volumes++
		}
	}
	if volumes != 1 {
		t.Fatalf("want exactly 1 Volume line for 1 declared volume, got %d\n%s", volumes, out)
	}
}

// quadletDirectives is every key renderQuadletUnit is allowed to emit. A rendered unit
// containing anything else means a value escaped its line — which is exactly how
// `PodmanArgs=--privileged` would arrive.
var quadletDirectives = map[string]bool{
	"Description": true, "Image": true, "ContainerName": true, "PublishPort": true,
	"Environment": true, "Secret": true, "Volume": true, "TimeoutStopSec": true,
	"Restart": true, "OOMScoreAdjust": true, "WantedBy": true,
	// The accessory unit's own two, both constants in its renderer. `Network` is what
	// scopes an accessory to one app, and `NetworkAlias` is the name that app resolves
	// it by — neither may ever arrive from a declared value.
	"Network": true, "NetworkAlias": true,
	// A process unit's command. A constant key; the value is argv, quoted per element.
	"Exec": true,
	// The container's own ceiling. Both are constants in the renderer — no declared
	// value reaches them — so they can only appear with the text below, and the
	// allowlist is what proves a smuggled `AddCapability` never could.
	"NoNewPrivileges": true, "DropCapability": true,
}
