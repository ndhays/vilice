package app

import "testing"

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
