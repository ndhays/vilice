package app

import (
	"strings"
	"testing"
)

// The release step runs a declared command once, from the new image, before the new
// color starts. See decisions/open/release-command.md. Everything below is the pure
// half — the shape of the command line and the rules it has to satisfy — which is where
// the mistakes that matter live.

func TestReleaseContainerIsNamedAfterTheSpec(t *testing.T) {
	// Named after the spec digest so a retry can tell "already running" from "already
	// succeeded" from "failed", rather than running a migration a second time.
	got := releaseContainer("web", "sha256:abcdef0123456789aaaa")
	if got != "web-release-abcdef012345" {
		t.Errorf("releaseContainer = %q", got)
	}

	// Two different release commands must never share a container name. They cannot,
	// because Release is inside the digest — this asserts that wiring, since without it
	// the name would collide and the second command would be skipped as "already done".
	base := appState{
		Name: "web", Image: "img@sha256:" + strings.Repeat("a", 64),
		Hostnames: []string{"x.example.com"}, Port: 8080, Health: "/",
	}
	migrate := base
	migrate.Release = []string{"bin/rails", "db:migrate"}
	seed := base
	seed.Release = []string{"bin/rails", "db:seed"}

	if appDigest(migrate) == appDigest(seed) {
		t.Fatal("the release command is not part of the spec digest — two commands share one identity")
	}
	if releaseContainer("web", appDigest(migrate)) == releaseContainer("web", appDigest(seed)) {
		t.Error("two release commands produced the same container name")
	}
}

// A release runs with what the app runs with — otherwise a migration cannot reach the
// database — and with the same ceiling, because a release step is not a chance to run
// with more than the app has.
func TestReleaseFlagsCarryTheAppsWorldAndItsCeiling(t *testing.T) {
	st := appState{
		Name: "web", Port: 8080,
		Env:         map[string]string{"RAILS_ENV": "production", "A_FLAG": "1"},
		Secrets:     []string{"DATABASE_URL"},
		SecretFiles: map[string]string{"config": "/etc/app/config.json"},
		Volumes:     []string{"web-data:/rails/storage"},
	}
	got := strings.Join(releaseFlags(st), " ")

	for _, want := range []string{
		"--security-opt no-new-privileges",
		"--cap-drop CAP_NET_BIND_SERVICE",
		"--cap-drop CAP_SYS_CHROOT",
		"--env PORT=8080",
		"--env A_FLAG=1", // sorted before RAILS_ENV
		"--env RAILS_ENV=production",
		"--secret web__DATABASE_URL,type=env,target=DATABASE_URL",
		"--secret web__config,type=mount,target=/etc/app/config.json",
		"--volume web-data:/rails/storage",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("release flags missing %q\n--- got ---\n%s", want, got)
		}
	}
}

// Vilice builds every flag. Nothing a caller declares may become one — that is what
// keeps `--privileged` from arriving inside a value, the same rule the Quadlet's
// directive allowlist enforces for the unit file.
func TestReleaseFlagsNeverGrowFromDeclaredValues(t *testing.T) {
	st := appState{
		Name: "web", Port: 8080,
		Env:     map[string]string{"EVIL": "x --privileged"},
		Volumes: []string{"data:/d"},
	}
	for _, arg := range releaseFlags(st) {
		if arg == "--privileged" || arg == "--user" || arg == "--cap-add" {
			t.Fatalf("a declared value became the flag %q", arg)
		}
	}
	// The hostile text survives as *one* argument — podman receives it as a value, and
	// argv has no place for it to split.
	joined := strings.Join(releaseFlags(st), "\x00")
	if !strings.Contains(joined, "EVIL=x --privileged") {
		t.Error("the env value should ride intact as a single argument")
	}
}

func TestValidRelease(t *testing.T) {
	if err := validRelease(nil); err != nil {
		t.Errorf("no release declared is the common case, not an error: %v", err)
	}
	if err := validRelease([]string{"bin/rails", "db:migrate"}); err != nil {
		t.Errorf("ordinary argv refused: %v", err)
	}
	if err := validRelease([]string{"  ", "db:migrate"}); err == nil {
		t.Error("a blank program should be refused")
	}
	// The command is echoed into a record entry and an error message, so a value that
	// can end its own line is refused here for the same reason the unit renderer does.
	if err := validRelease([]string{"bin/rails", "db:migrate\nInjected=1"}); err == nil {
		t.Error("a control character should be refused")
	}
}

// A release is argv, so it can never be a shell string. This is no-key-gets-a-shell one
// level down: a multi-step release belongs in a script inside the image, where the digest
// covers what it does.
func TestReleaseIsArgvNotAShell(t *testing.T) {
	st := appState{Name: "web", Port: 8080, Release: []string{"bin/rails", "db:migrate"}}
	for _, a := range releaseFlags(st) {
		if a == "sh" || a == "-lc" || a == "-c" {
			t.Fatalf("the release step invoked a shell (%q)", a)
		}
	}
}

// validateState is the door every spec comes through, whether from flags or stdin.
func TestValidateStateChecksTheReleaseCommand(t *testing.T) {
	st := appState{
		Name: "web", Image: "img@sha256:" + strings.Repeat("a", 64),
		Hostnames: []string{"app.example.com"}, Port: 8080, Health: "/",
		Release: []string{"bin/rails", "db:migrate\nInjected=1"},
	}
	if err := validateState(st); err == nil {
		t.Error("validateState let a control character through in the release command")
	}
}
