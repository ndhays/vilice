package core

// Which binary this box authorized, and proof that it is the binary that ran.
//
//	/etc/vilice/binary.digest   the sha256 of the vilice binary `prepare` recorded
//
// Root-owned, at a fixed path. Before a verb acts, the core hashes the running
// executable and compares it to that line: swap /usr/local/bin/vilice and the verb
// refuses, and the refusal is recorded. This is the digest-pinning rule Vilice
// already applies to container images, turned on itself.
//
// The path is not configurable. A knob that redirects it — a flag, an environment
// variable, a config key — hands the check to whoever controls the environment, and
// ambient trust of that kind is what the design exists to refuse. An admin who wants
// a different location recompiles or bind-mounts; the friction is the point.
//
// Not every verb is checked. `verify`, `record`, `actors`, `authorize`, `revoke` and
// the root ceiling keep working when the file is missing or does not match, so an
// operator can inspect and repair a box whose binary was replaced rather than being
// locked out by the integrity check itself. `prepare` is the repair: it re-records
// the digest. See decisions/roles-not-packs.md.

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// binaryDigestPath is a package var rather than a const *only* so the tests in this
// package can point it at a temp dir — deliberately not reachable from a flag or the
// environment, which is the whole point.
var binaryDigestPath = "/etc/vilice/binary.digest"

// BinaryDigestPath is the file naming the binary this box authorized.
func BinaryDigestPath() string { return binaryDigestPath }

var (
	selfDigestOnce sync.Once
	selfDigestVal  string
	selfDigestErr  error
)

// SelfDigest is the sha256 of the running binary, computed once.
func SelfDigest() (string, error) {
	selfDigestOnce.Do(func() {
		self, err := os.Executable()
		if err != nil {
			selfDigestErr = err
			return
		}
		selfDigestVal, selfDigestErr = fileDigest(self)
	})
	return selfDigestVal, selfDigestErr
}

// fileDigest hashes a file by opening it once and hashing that descriptor, never the
// path — so what was hashed and what is on disk cannot be two different files.
func fileDigest(path string) (string, error) {
	f, err := os.Open(path) // #nosec G304 -- our own binary
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil)), nil
}

// readBinaryDigest parses the file. Line-oriented and plain on purpose — like
// authorized_keys, it should be readable with `cat` by an admin who has never used
// Vilice. Blank lines and # comments are ignored; one digest is expected.
func readBinaryDigest(path string) (string, error) {
	f, err := os.Open(path) // #nosec G304 -- the fixed, root-owned path
	if err != nil {
		return "", err
	}
	defer f.Close()

	digest := ""
	sc := bufio.NewScanner(f)
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimSpace(sc.Text())
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		if digest != "" {
			return "", fmt.Errorf("%s:%d: a box authorizes one binary; got a second digest", path, line)
		}
		if strings.Fields(text)[0] != text {
			return "", fmt.Errorf("%s:%d: want a bare 'sha256:...', got %q", path, line, text)
		}
		if !strings.HasPrefix(text, "sha256:") {
			return "", fmt.Errorf("%s:%d: digest must be sha256:<hex>, got %q", path, line, text)
		}
		digest = text
	}
	if err := sc.Err(); err != nil {
		return "", err
	}
	if digest == "" {
		return "", fmt.Errorf("%s: no digest in the file", path)
	}
	return digest, nil
}

// renderBinaryDigest is the file `prepare` lays down.
func renderBinaryDigest(digest string) string {
	return "# Managed by `vilice prepare`. The sha256 of the vilice binary this box\n" +
		"# authorized. Every verb that acts checks the running binary against it.\n" +
		digest + "\n"
}

// writeBinaryDigest records the running binary as the one this box authorizes, and
// returns the digest written. Root-only in practice: the file lives under /etc.
func writeBinaryDigest() (string, error) {
	digest, err := SelfDigest()
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(binaryDigestPath), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(binaryDigestPath, []byte(renderBinaryDigest(digest)), 0o644); err != nil { // #nosec G306 -- read by the unprivileged _vilice user; root owns the write
		return "", err
	}
	return digest, nil
}

// checkBinaryDigest compares the running binary against the recorded one and returns
// its digest. It is on the hot path for every verb that acts, not a check that gets
// switched on later: a mechanism nobody has exercised is a mechanism nobody has
// tested.
//
// A missing file is a refusal, not a default-allow. The box either said which binary
// may run or it did not.
func checkBinaryDigest() (string, error) {
	recorded, err := readBinaryDigest(binaryDigestPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("this box has not said which binary may run (%s is missing) — run `vilice prepare`", binaryDigestPath)
		}
		return "", err
	}
	digest, err := SelfDigest()
	if err != nil {
		return "", fmt.Errorf("reading this binary's digest: %w", err)
	}
	if recorded != digest {
		return "", fmt.Errorf("this box authorized %s but the running binary is %s — "+
			"they disagree; re-run `vilice prepare` after an upgrade, and look at the "+
			"record if you did not upgrade", recorded, digest)
	}
	return digest, nil
}
