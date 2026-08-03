package app

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestRegistryOf(t *testing.T) {
	cases := map[string]string{
		"nginx@sha256:abc":                              "docker.io",
		"library/nginx@sha256:abc":                      "docker.io",
		"docker.io/library/nginx@sha256:abc":            "docker.io",
		"ghcr.io/project-zot/zot@sha256:abc":            "ghcr.io",
		"registry.example.com/team/app@sha256:abc":      "registry.example.com",
		"registry.example.com:5000/team/app@sha256:abc": "registry.example.com:5000",
		"localhost:5000/app@sha256:abc":                 "localhost:5000",
		"quay.io/prometheus/node-exporter":              "quay.io",
	}
	for image, want := range cases {
		if got := registryOf(image); got != want {
			t.Errorf("registryOf(%q) = %q, want %q", image, got, want)
		}
	}
}

func TestClassifyPullError(t *testing.T) {
	cases := []struct {
		name       string
		out        string
		wantCode   string
		wantRetry  bool
		wantInHint string
	}{
		{"auth", "Error: initializing source: unauthorized: authentication required", "registry_auth", true, "registry-login"},
		{"denied", "Error: denied: requested access to the resource is denied", "registry_auth", true, "registry-login"},
		{"unreachable", "Error: pinging container registry ghcr.io: dial tcp: lookup ghcr.io: no such host", "registry_unreachable", true, "ghcr.io"},
		{"notfound", "Error: reading manifest sha256:abc: manifest unknown", "image_not_found", false, "not found"},
		{"other", "Error: something else broke", "pull_failed", true, "failed"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, retry, hint := classifyPullError("ghcr.io", c.out)
			if code != c.wantCode {
				t.Errorf("code = %q, want %q", code, c.wantCode)
			}
			if retry != c.wantRetry {
				t.Errorf("retryable = %v, want %v", retry, c.wantRetry)
			}
			if !strings.Contains(hint, c.wantInHint) {
				t.Errorf("hint %q does not contain %q", hint, c.wantInHint)
			}
		})
	}
}

func TestValidRegistry(t *testing.T) {
	good := []string{"ghcr.io", "registry.example.com", "registry.example.com:5000", "localhost:5000", "docker.io"}
	bad := []string{"", "ghcr.io/path", "has space", "reg/with/slash", "bad$char"}
	for _, s := range good {
		if !validRegistry(s) {
			t.Errorf("validRegistry(%q) = false, want true", s)
		}
	}
	for _, s := range bad {
		if validRegistry(s) {
			t.Errorf("validRegistry(%q) = true, want false", s)
		}
	}
}

func TestParseAuthFile(t *testing.T) {
	ghcrAuth := base64.StdEncoding.EncodeToString([]byte("nick:s3cret-token"))
	dockerAuth := base64.StdEncoding.EncodeToString([]byte("robot")) // no colon → no username parsed
	data := []byte(`{"auths":{"ghcr.io":{"auth":"` + ghcrAuth + `"},"registry.example.com":{"auth":"` + dockerAuth + `"}}}`)

	regs := parseAuthFile(data)
	if len(regs) != 2 {
		t.Fatalf("got %d registries, want 2", len(regs))
	}
	// Sorted by host: ghcr.io first.
	if regs[0].Host != "ghcr.io" || regs[0].Username != "nick" {
		t.Errorf("entry 0 = %+v, want ghcr.io/nick", regs[0])
	}
	if regs[1].Host != "registry.example.com" || regs[1].Username != "" {
		t.Errorf("entry 1 = %+v, want registry.example.com with empty username", regs[1])
	}
	// The password must never appear in the redacted ledger.
	for _, r := range regs {
		if strings.Contains(r.Username, "s3cret") {
			t.Errorf("password leaked into username: %q", r.Username)
		}
	}
}

func TestParseAuthFileGarbage(t *testing.T) {
	if regs := parseAuthFile([]byte("not json")); regs != nil {
		t.Errorf("garbage auth file should parse to nil, got %+v", regs)
	}
	if regs := parseAuthFile([]byte(`{"auths":{}}`)); len(regs) != 0 {
		t.Errorf("empty auths should yield no registries, got %+v", regs)
	}
}

func TestRegistryCoverageCheck(t *testing.T) {
	apps := []appState{
		{Name: "a", Image: "ghcr.io/me/a@sha256:1"},
		{Name: "b", Image: "ghcr.io/me/b@sha256:2"}, // same registry, deduped
		{Name: "c", Image: "nginx@sha256:3"},        // docker.io, no login
	}
	logins := []registryLogin{{Host: "ghcr.io", Username: "me"}}

	c := registryCoverageCheck(apps, logins)
	if !c.OK {
		t.Error("coverage check should stay OK (informational), got FAIL")
	}
	if !strings.Contains(c.Note, "logged in: ghcr.io") {
		t.Errorf("note %q missing logged-in registry", c.Note)
	}
	if !strings.Contains(c.Note, "docker.io") {
		t.Errorf("note %q should flag the un-logged-in registry", c.Note)
	}
	// ghcr.io appears once despite two apps.
	if strings.Count(c.Note, "ghcr.io") != 1 {
		t.Errorf("ghcr.io should be deduped, note = %q", c.Note)
	}
}

func TestRegistryCoverageNoApps(t *testing.T) {
	c := registryCoverageCheck(nil, nil)
	if !c.OK || !strings.Contains(c.Note, "no app registries") {
		t.Errorf("empty coverage = %+v", c)
	}
}

func TestRegistryLoginArgValidation(t *testing.T) {
	// These all fail before any podman call, so they're safe to run without podman.
	if r := registryLoginCmd([]string{"--username", "u"}); r.Code != "bad_args" {
		t.Errorf("missing registry: got %q", r.Code)
	}
	if r := registryLoginCmd([]string{"ghcr.io/bad/path", "--username", "u"}); r.Code != "bad_args" {
		t.Errorf("bad registry: got %q", r.Code)
	}
	if r := registryLoginCmd([]string{"ghcr.io"}); r.Code != "bad_args" {
		t.Errorf("missing username: got %q", r.Code)
	}
	if r := registryLogoutCmd(nil); r.Code != "bad_args" {
		t.Errorf("logout missing registry: got %q", r.Code)
	}
}

func TestResultFromErr(t *testing.T) {
	coded := &codedError{code: "registry_auth", retryable: true, msg: "expired"}
	r := resultFromErr(coded, "deploy_failed")
	if r.Code != "registry_auth" || !r.Retryable || r.Message != "expired" {
		t.Errorf("coded error not preserved: %+v", r)
	}
	r = resultFromErr(errPlain("boom"), "deploy_failed")
	if r.Code != "deploy_failed" || !r.Retryable {
		t.Errorf("plain error should fall back: %+v", r)
	}
}

type errPlain string

func (e errPlain) Error() string { return string(e) }
