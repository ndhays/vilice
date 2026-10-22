package app

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseMaintenance(t *testing.T) {
	dump := `APT::Architecture "amd64";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";`
	mw := parseMaintenance(dump)
	if mw == nil {
		t.Fatal("expected a maintenance window")
	}
	if mw["reboot_time"] != "04:00" {
		t.Errorf("reboot_time = %v, want 04:00", mw["reboot_time"])
	}
	if mw["auto_reboot"] != true {
		t.Errorf("auto_reboot = %v, want true", mw["auto_reboot"])
	}
	// No reboot time configured → no window to report.
	if parseMaintenance(`APT::Architecture "amd64";`) != nil {
		t.Error("expected nil when no reboot time is set")
	}
}

func TestParseUptime(t *testing.T) {
	if got := parseUptime("12345.67 8901.23\n"); got != 12345 {
		t.Errorf("parseUptime = %d, want 12345", got)
	}
	if got := parseUptime(""); got != 0 {
		t.Errorf("parseUptime(empty) = %d, want 0", got)
	}
}

func TestParseLoadavg(t *testing.T) {
	if got := parseLoadavg("0.42 0.10 0.05 1/234 5678\n"); got != 0.42 {
		t.Errorf("parseLoadavg = %v, want 0.42", got)
	}
}

func TestParseMeminfo(t *testing.T) {
	sample := "MemTotal:       16384000 kB\nMemFree:         1000000 kB\nMemAvailable:    8192000 kB\n"
	total, avail := parseMeminfo(sample)
	if total != 16384000 {
		t.Errorf("total = %d, want 16384000", total)
	}
	if avail != 8192000 {
		t.Errorf("available = %d, want 8192000", avail)
	}
}

func TestParsePodmanPS(t *testing.T) {
	sample := "web-a\tghcr.io/org/web@sha256:abc0000000000000000000000000000000000000000000000000000000000000\tUp 3 hours\nmy-api-b\tghcr.io/org/api@sha256:def0000000000000000000000000000000000000000000000000000000000000\tExited (0)\n"
	apps := parsePodmanPS(sample)
	if len(apps) != 2 {
		t.Fatalf("got %d apps, want 2", len(apps))
	}
	// The color suffix is split off: Name is the command target, Color is the blue/green.
	if apps[0].Name != "web" || apps[0].Color != "a" || apps[0].Image != "ghcr.io/org/web@sha256:abc0000000000000000000000000000000000000000000000000000000000000" || apps[0].State != "Up 3 hours" {
		t.Errorf("apps[0] = %+v", apps[0])
	}
	// App names may contain hyphens; only the trailing -a/-b is the color.
	if apps[1].Name != "my-api" || apps[1].Color != "b" || apps[1].State != "Exited (0)" {
		t.Errorf("apps[1] = %+v", apps[1])
	}
	// A name without a color suffix is left unchanged.
	if got := parsePodmanPS("plain\timg\tUp"); got[0].Name != "plain" || got[0].Color != "" {
		t.Errorf("unsuffixed name should be unchanged: %+v", got[0])
	}
	if got := parsePodmanPS("  \n"); got != nil {
		t.Errorf("empty input should give no apps, got %v", got)
	}
}

func TestHumanBytes(t *testing.T) {
	cases := map[uint64]string{
		512:                    "512B",
		1024:                   "1.0KB",
		1024 * 1024:            "1.0MB",
		3 * 1024 * 1024 * 1024: "3.0GB",
	}
	for n, want := range cases {
		if got := humanBytes(n); got != want {
			t.Errorf("humanBytes(%d) = %q, want %q", n, got, want)
		}
	}
}

// A restart is owed when the flag file exists, and the packages that asked are named
// once each. No flag is "not required" — stated, not omitted.
func TestCollectRebootReadsTheFlag(t *testing.T) {
	dir := t.TempDir()
	flag := filepath.Join(dir, "reboot-required")

	if r := collectReboot(flag); r.Required || len(r.Packages) != 0 {
		t.Errorf("no flag file should mean no restart owed: %+v", r)
	}

	if err := os.WriteFile(flag, []byte("*** System restart required ***\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if r := collectReboot(flag); !r.Required || len(r.Packages) != 0 {
		t.Errorf("the flag alone is enough, with no packages named: %+v", r)
	}

	pkgs := "linux-image-6.8.0-45-generic\nlibc6\nlinux-image-6.8.0-45-generic\n\n"
	if err := os.WriteFile(flag+".pkgs", []byte(pkgs), 0o644); err != nil {
		t.Fatal(err)
	}
	r := collectReboot(flag)
	if want := []string{"linux-image-6.8.0-45-generic", "libc6"}; !reflect.DeepEqual(r.Packages, want) {
		t.Errorf("packages = %v, want %v", r.Packages, want)
	}
}

// A stopped app has no container, so Podman does not list it. It is still deployed here,
// and status has to say so — it is the only way back to `start`.
func TestWithDeployedKeepsAStoppedApp(t *testing.T) {
	running := parsePodmanPS("web-a\timg@sha256:aa\tUp 3 hours\nweb-db\tpostgres\tUp 3 hours\n")
	deployed := []appState{
		{Name: "web", Image: "img@sha256:aa", Hostnames: []string{"web.example"}, PrevImage: "img@sha256:00"},
		{Name: "blog", Image: "img@sha256:bb", Hostnames: []string{"blog.example"}},
	}
	apps := withDeployed(running, deployed)
	if len(apps) != 3 {
		t.Fatalf("got %d entries, want 3: %+v", len(apps), apps)
	}
	web, db, blog := apps[0], apps[1], apps[2]
	if web.State != "Up 3 hours" || !web.Rollback || len(web.Hostnames) != 1 || web.Hostnames[0] != "web.example" {
		t.Errorf("a running app keeps Podman's state and gains its hostnames and rollback: %+v", web)
	}
	if db.Hostnames != nil || db.Rollback {
		t.Errorf("an accessory's container is not a deployed app: %+v", db)
	}
	if blog.Name != "blog" || blog.State != stateStopped || blog.Image != "img@sha256:bb" || blog.Rollback {
		t.Errorf("a deployed app with no container is listed as stopped: %+v", blog)
	}
	if got := withDeployed(nil, nil); got != nil {
		t.Errorf("nothing running and nothing deployed is no apps, got %v", got)
	}
}

func TestParseMemoryCurrent(t *testing.T) {
	cases := map[string]uint64{
		"327155712\n":            327155712,
		"[not set]\n":            0,
		"18446744073709551615\n": 0, // how older systemd spells "not set"
		"":                       0,
		"infinity":               0,
	}
	for in, want := range cases {
		if got := parseMemoryCurrent(in); got != want {
			t.Errorf("parseMemoryCurrent(%q) = %d, want %d", in, got, want)
		}
	}
}
