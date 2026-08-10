package app

import (
	"strings"
	"testing"
)

func TestParsePodmanVersion(t *testing.T) {
	cases := []struct {
		out      string
		maj, min int
		ok       bool
	}{
		{"podman version 5.7.0", 5, 7, true},
		{"podman version 4.4.0", 4, 4, true},
		{"  podman version 4.9.3  \n", 4, 9, true},
		{"5.7.0", 5, 7, true}, // bare version
		{"podman version", 0, 0, false},
		{"", 0, 0, false},
		{"podman version x.y.z", 0, 0, false},
	}
	for _, c := range cases {
		maj, min, ok := parsePodmanVersion(c.out)
		if ok != c.ok || (ok && (maj != c.maj || min != c.min)) {
			t.Errorf("parsePodmanVersion(%q) = %d,%d,%v; want %d,%d,%v", c.out, maj, min, ok, c.maj, c.min, c.ok)
		}
	}
}

func TestQuadletReady(t *testing.T) {
	cases := []struct {
		maj, min int
		want     bool
	}{
		{5, 7, true},
		{4, 4, true}, // exactly the floor
		{4, 9, true},
		{4, 3, false}, // one minor short
		{3, 9, false}, // old major
		{5, 0, true},
	}
	for _, c := range cases {
		if got := quadletReady(c.maj, c.min); got != c.want {
			t.Errorf("quadletReady(%d,%d) = %v, want %v", c.maj, c.min, got, c.want)
		}
	}
}

// Ghost containers: conmon processes under any uid but ours mean an app was
// deployed by steward run as the wrong user — running, but invisible to us.
// Upgrading to a different path is the quiet way to break every scoped key: prepare
// rewrites the snapshot unit, but only `authorize` rewrites a key's forced command, so
// the ledger keeps pointing at a binary that is no longer there.
func TestBinaryPathCheck(t *testing.T) {
	const self = "/usr/local/bin/steward"
	unit := func(p string) string {
		return "[Service]\nType=oneshot\nUser=steward\nExecStart=" + p + " snapshot\n"
	}
	keys := func(p string) string {
		return `command="` + p + ` _exec --client console --scope operate",restrict ssh-ed25519 AAAA sw@host` + "\n" +
			`command="` + p + ` _exec --client ci --scope observe",restrict ssh-ed25519 BBBB ci@host` + "\n"
	}

	t.Run("everything agrees", func(t *testing.T) {
		if c := binaryPathCheck(self, unit(self), keys(self)); !c.OK {
			t.Errorf("want OK, got %+v", c)
		}
	})

	t.Run("nothing installed yet", func(t *testing.T) {
		if c := binaryPathCheck(self, "", ""); !c.OK {
			t.Errorf("an unprovisioned box has nothing to compare; got %+v", c)
		}
	})

	t.Run("the ledger is stale", func(t *testing.T) {
		c := binaryPathCheck(self, unit(self), keys("/opt/steward/bin/steward"))
		if c.OK {
			t.Fatal("a ledger pointing at another binary should fail the check")
		}
		for _, want := range []string{"/opt/steward/bin/steward", "scoped key", "re-authorize"} {
			if !strings.Contains(c.Note, want) {
				t.Errorf("note should mention %q; got %q", want, c.Note)
			}
		}
	})

	t.Run("the timer is stale", func(t *testing.T) {
		c := binaryPathCheck(self, unit("/usr/bin/steward"), keys(self))
		if c.OK || !strings.Contains(c.Note, "snapshot timer") {
			t.Errorf("want a snapshot-timer drift report, got %+v", c)
		}
	})

	t.Run("a key with no forced command is ignored", func(t *testing.T) {
		plain := "ssh-ed25519 AAAA someone@laptop\n"
		if c := binaryPathCheck(self, unit(self), plain); !c.OK {
			t.Errorf("an unpinned key says nothing about the binary path; got %+v", c)
		}
	})
}

func TestGhostContainerCheck(t *testing.T) {
	self := 990
	cases := []struct {
		name string
		ps   string
		ok   bool
		note string
	}{
		{"clean box", "  990 conmon\n  990 conmon\n    0 sshd\n 1000 bash\n", true, ""},
		{"root ghost", "    0 conmon\n  990 conmon\n", false, "1 under uid 0"},
		{"two ghosts one uid", "    0 conmon\n    0 conmon\n", false, "2 under uid 0"},
		{"no containers at all", "    0 sshd\n 1000 bash\n", true, ""},
	}
	for _, c := range cases {
		got := ghostContainerCheck(c.ps, self)
		if got.OK != c.ok {
			t.Errorf("%s: OK = %v, want %v (note %q)", c.name, got.OK, c.ok, got.Note)
		}
		if c.note != "" && !strings.Contains(got.Note, c.note) {
			t.Errorf("%s: note %q missing %q", c.name, got.Note, c.note)
		}
	}
}
