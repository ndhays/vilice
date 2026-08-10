package app

import (
	"reflect"
	"strings"
	"testing"
)

func TestParseDeployArgs(t *testing.T) {
	st, err := parseDeployArgs([]string{
		"web", "--image", "ghcr.io/org/web@sha256:abc1230000000000000000000000000000000000000000000000000000000000", "--hostname", "web.example.com",
		"--port", "3000", "--health", "/healthz",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if st.Name != "web" || st.Port != 3000 || st.Health != "/healthz" || len(st.Hostnames) != 1 || st.Hostnames[0] != "web.example.com" {
		t.Errorf("parsed = %+v", st)
	}
}

func TestParseDeployArgsDefaults(t *testing.T) {
	st, err := parseDeployArgs([]string{"web", "--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", "--hostname", "h"})
	if err != nil {
		t.Fatal(err)
	}
	if st.Port != 8080 {
		t.Errorf("default port = %d, want 8080", st.Port)
	}
	if st.Health != "/" {
		t.Errorf("default health = %q, want /", st.Health)
	}
}

func TestParseDeployArgsRejects(t *testing.T) {
	cases := []struct {
		name string
		args []string
	}{
		{"no app", []string{"--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", "--hostname", "h"}},
		{"no image", []string{"web", "--hostname", "h"}},
		{"tag not digest", []string{"web", "--image", "nginx:latest", "--hostname", "h"}},
		{"no hostname", []string{"web", "--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000"}},
		{"bad app name", []string{"we b", "--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", "--hostname", "h"}},
	}
	for _, c := range cases {
		if _, err := parseDeployArgs(c.args); err == nil {
			t.Errorf("%s: expected an error", c.name)
		}
	}
}

func TestAppDigestOrderIndependentAndContentSensitive(t *testing.T) {
	a := appState{
		Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"b.example", "a.example"}, Port: 8080, Health: "/",
		Env: map[string]string{"B": "2", "A": "1"}, Secrets: []string{"K2", "K1"}, Volumes: []string{"v2", "v1"},
	}
	b := appState{
		Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"a.example", "b.example"}, Port: 8080, Health: "/",
		Env: map[string]string{"A": "1", "B": "2"}, Secrets: []string{"K1", "K2"}, Volumes: []string{"v1", "v2"},
	}
	if appDigest(a) != appDigest(b) {
		t.Error("digest must be order-independent for env/secrets/volumes")
	}

	c := a
	c.Image = "x@sha256:def0000000000000000000000000000000000000000000000000000000000000"
	if appDigest(a) == appDigest(c) {
		t.Error("digest must change when the image changes")
	}

	// Runtime fields and the app name are not part of the config digest.
	d := a
	d.Name = "other"
	d.HostPort = 49999
	d.PrevImage = "y@sha256:01d0000000000000000000000000000000000000000000000000000000000000"
	if appDigest(a) != appDigest(d) {
		t.Error("runtime fields / name must not affect the config digest")
	}

	// secret_files are recorded config: adding one, or changing its path, changes the digest.
	e := a
	e.SecretFiles = map[string]string{"config": "/etc/app/config.json"}
	f := a
	f.SecretFiles = map[string]string{"config": "/etc/app/other.json"}
	if appDigest(a) == appDigest(e) {
		t.Error("adding a secret file must change the digest")
	}
	if appDigest(e) == appDigest(f) {
		t.Error("changing a secret-file path must change the digest")
	}

	// The backup hook is recorded config: changing it changes the digest.
	g := a
	g.Backup = "pg_dump -Fc -f /data/dump.pgc"
	if appDigest(a) == appDigest(g) {
		t.Error("setting the backup hook must change the digest")
	}
}

func TestParseEnvelope(t *testing.T) {
	data := []byte(`{"app":{"image":"x@sha256:abc0000000000000000000000000000000000000000000000000000000000000","hostnames":["h1","h2"],"port":8080,"secrets":["K"]},"secret_values":{"K":"v"}}`)
	env, err := parseEnvelope(data)
	if err != nil {
		t.Fatal(err)
	}
	if env.App.Image != "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000" || len(env.App.Secrets) != 1 || env.App.Secrets[0] != "K" {
		t.Errorf("spec parsed wrong: %+v", env.App)
	}
	if len(env.App.Hostnames) != 2 || env.App.Hostnames[0] != "h1" {
		t.Errorf("hostnames parsed wrong: %+v", env.App.Hostnames)
	}
	if env.SecretValues["K"] != "v" {
		t.Errorf("secret value parsed wrong: %+v", env.SecretValues)
	}
	if _, err := parseEnvelope([]byte("not json")); err == nil {
		t.Error("expected an error on invalid JSON")
	}
}

func TestStateFromSpec(t *testing.T) {
	st, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"}})
	if err != nil {
		t.Fatal(err)
	}
	if st.Port != 8080 || st.Health != "/" {
		t.Errorf("defaults not applied: %+v", st)
	}
	if st.Digest == "" {
		t.Error("digest not stamped")
	}
	// Invalid secret / env names are rejected.
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"}, Secrets: []string{"bad name"}}); err == nil {
		t.Error("expected invalid secret name to fail")
	}
	if _, err := stateFromSpec("web", appSpec{Image: "nginx:latest", Hostnames: []string{"h"}}); err == nil {
		t.Error("expected non-digest image to fail")
	}
	// Missing hostname is rejected.
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000"}); err == nil {
		t.Error("expected missing hostname to fail")
	}
	// A privileged port is rejected (containers are unprivileged).
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"}, Port: 80}); err == nil {
		t.Error("expected port 80 (<1024) to be rejected")
	}
	// A file secret with an absolute path is accepted; a relative one is not.
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"},
		SecretFiles: map[string]string{"config": "/etc/app/config.json"}}); err != nil {
		t.Errorf("valid file secret should pass: %v", err)
	}
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"},
		SecretFiles: map[string]string{"config": "etc/app/config.json"}}); err == nil {
		t.Error("relative secret-file path must be rejected")
	}
	// A name declared as both an env secret and a file is ambiguous → rejected.
	if _, err := stateFromSpec("web", appSpec{Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"},
		Secrets: []string{"X"}, SecretFiles: map[string]string{"X": "/etc/x"}}); err == nil {
		t.Error("a secret declared as both env and file must be rejected")
	}
}

func TestPutSecretsValidates(t *testing.T) {
	st := appState{Name: "web", Secrets: []string{"A"}}
	// A value for an undeclared secret is rejected (before touching podman).
	if err := putSecrets(st, map[string]string{"B": "x"}); err == nil {
		t.Error("undeclared secret value must be rejected")
	}
	// A declared secret with no value is rejected (self-contained deploys).
	if err := putSecrets(st, map[string]string{}); err == nil {
		t.Error("declared secret with no value must be rejected")
	}
	// No declared secrets, no values → nothing to do, no podman call.
	if err := putSecrets(appState{Name: "web"}, nil); err != nil {
		t.Errorf("empty secrets should be a no-op: %v", err)
	}
	// File secrets share the store and the same checks (both fail before any podman call).
	fs := appState{Name: "web", SecretFiles: map[string]string{"config": "/etc/app/config.json"}}
	if err := putSecrets(fs, map[string]string{}); err == nil {
		t.Error("declared file secret with no value must be rejected")
	}
	if err := putSecrets(fs, map[string]string{"other": "x"}); err == nil {
		t.Error("undeclared file-secret value must be rejected")
	}
}

func TestRenderCaddyfile(t *testing.T) {
	apps := []appState{
		{Hostnames: []string{"web.example.com", "www.example.com"}, HostPort: 49153},
		{Hostnames: []string{"http://api.test"}, HostPort: 49154},
	}
	got := renderCaddyfile(apps)
	for _, want := range []string{
		"web.example.com www.example.com {", "reverse_proxy 127.0.0.1:49153",
		"http://api.test {", "reverse_proxy 127.0.0.1:49154",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("Caddyfile missing %q\n%s", want, got)
		}
	}
	// No apps must still be a valid (non-empty) Caddy config, not "".
	if empty := renderCaddyfile(nil); !strings.HasPrefix(empty, "#") {
		t.Errorf("empty Caddyfile should be a comment, got %q", empty)
	}
}

func TestShortDigest(t *testing.T) {
	if got := shortDigest("ghcr.io/org/web@sha256:abcdef0123456789000000000000000000000000000000000000000000000000"); got != "sha256:abcdef012345" {
		t.Errorf("shortDigest = %q", got)
	}
}

func TestAppStateRoundTrip(t *testing.T) {
	t.Setenv("STEWARD_APPS_DIR", t.TempDir())
	in := appState{
		Name: "web", Image: "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", Hostnames: []string{"h"}, Port: 8080, Health: "/",
		Env: map[string]string{"RAILS_ENV": "production"}, Secrets: []string{"RAILS_MASTER_KEY"},
		Volumes: []string{"web-data:/rails/storage"}, Digest: "sha256:deadbeef", HostPort: 49153,
	}
	if err := saveApp(in); err != nil {
		t.Fatal(err)
	}
	out, ok := loadApp("web")
	if !ok || !reflect.DeepEqual(out, in) {
		t.Errorf("round-trip: got %+v (%v), want %+v", out, ok, in)
	}
	apps, err := listApps()
	if err != nil || len(apps) != 1 {
		t.Fatalf("listApps = %v, %v", apps, err)
	}
	if err := removeApp("web"); err != nil {
		t.Fatal(err)
	}
	if _, ok := loadApp("web"); ok {
		t.Error("app still present after removeApp")
	}
}

// remove must clean up file secrets too, not just env secrets — both live in the same
// Podman store, so declaredSecretNames must cover both or a file secret orphans.
func TestDeclaredSecretNames(t *testing.T) {
	st := appState{
		Name:        "web",
		Secrets:     []string{"DB_PASS", "API_KEY"},
		SecretFiles: map[string]string{"tls_cert": "/etc/tls/cert.pem"},
	}
	got := declaredSecretNames(st)
	want := map[string]bool{"DB_PASS": true, "API_KEY": true, "tls_cert": true}
	if len(got) != len(want) {
		t.Fatalf("declaredSecretNames = %v, want %d names", got, len(want))
	}
	for _, n := range got {
		if !want[n] {
			t.Errorf("unexpected secret name %q in %v", n, got)
		}
		delete(want, n)
	}
	if len(want) != 0 {
		t.Errorf("missing secret names: %v", want)
	}
}

// A digest pin has to be a digest, not merely carry the marker. The failure this guards
// against is real and was hit in practice: pasting a value that already includes its own
// "sha256:" prefix yields `…@sha256:sha256:abc…`, which satisfies a contains-check and
// then dies at the container runtime with "invalid reference format" — a message that
// tells the operator nothing about what they typed.
func TestValidDigestPin(t *testing.T) {
	good := "codeberg.org/forgejo/forgejo@sha256:" + strings.Repeat("a", 64)
	if err := validDigestPin(good); err != nil {
		t.Errorf("validDigestPin(good) = %v", err)
	}

	// The doubled prefix — and the error hands back the corrected reference, so the fix
	// is copy-pasteable rather than something to work out.
	doubled := "codeberg.org/forgejo/forgejo@sha256:sha256:" + strings.Repeat("b", 64)
	err := validDigestPin(doubled)
	if err == nil {
		t.Fatal("a doubled sha256: prefix must be refused")
	}
	if !strings.Contains(err.Error(), "doubled") {
		t.Errorf("the error should name the mistake, got %q", err)
	}
	if !strings.Contains(err.Error(), "@sha256:"+strings.Repeat("b", 64)) {
		t.Errorf("the error should offer the corrected reference, got %q", err)
	}

	// Truncated and non-hex are both refused, each with its own reason.
	if err := validDigestPin("x@sha256:abc"); err == nil || !strings.Contains(err.Error(), "64 hex") {
		t.Errorf("a short digest should be refused by length, got %v", err)
	}
	if err := validDigestPin("x@sha256:" + strings.Repeat("g", 64)); err == nil ||
		!strings.Contains(err.Error(), "non-hex") {
		t.Errorf("a non-hex digest should be refused, got %v", err)
	}

	// An unpinned image is the *other* check's business; this one stays quiet so the
	// operator gets one clear error rather than two overlapping ones.
	if err := validDigestPin("codeberg.org/forgejo/forgejo:12"); err != nil {
		t.Errorf("validDigestPin should not duplicate the missing-pin error, got %v", err)
	}
}
