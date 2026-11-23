package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckOSAcceptsOnlyDebian13(t *testing.T) {
	cases := []struct {
		name, release string
		ok            bool
	}{
		{"debian 13", "PRETTY_NAME=\"Debian GNU/Linux 13 (trixie)\"\nID=debian\nVERSION_ID=\"13\"\n", true},
		{"debian 12", "PRETTY_NAME=\"Debian GNU/Linux 12 (bookworm)\"\nID=debian\nVERSION_ID=\"12\"\n", false},
		{"ubuntu", "PRETTY_NAME=\"Ubuntu 26.04 LTS\"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID=\"26.04\"\n", false},
		{"debian testing", "PRETTY_NAME=\"Debian GNU/Linux forky/sid\"\nID=debian\n", false},
		{"empty", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "os-release")
			if err := os.WriteFile(path, []byte(c.release), 0o600); err != nil {
				t.Fatal(err)
			}
			err := checkOS(readOSRelease(path))
			if (err == nil) != c.ok {
				t.Fatalf("checkOS = %v, want ok=%v", err, c.ok)
			}
			if err != nil && !strings.Contains(err.Error(), "Debian 13") {
				t.Errorf("refusal %q doesn't name what is supported", err)
			}
		})
	}
}

func TestCheckOSNamesWhatItFound(t *testing.T) {
	err := checkOS(map[string]string{"ID": "ubuntu", "VERSION_ID": "26.04", "PRETTY_NAME": "Ubuntu 26.04 LTS"})
	if err == nil || !strings.Contains(err.Error(), "Ubuntu 26.04 LTS") {
		t.Fatalf("got %v", err)
	}
}

func TestReadOSReleaseMissingFile(t *testing.T) {
	if m := readOSRelease(filepath.Join(t.TempDir(), "none")); len(m) != 0 {
		t.Fatalf("got %v", m)
	}
}
