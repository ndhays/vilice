package core

// Which code is allowed to run here, and proof that it is the code that ran.
//
// Two files, both root-owned, doing two different jobs:
//
//	/usr/libexec/steward/         the shelf — where pack binaries live
//	/etc/steward/packs.manifest   the manifest — which packs may run, at which digest
//
// The directory locates; the manifest authorizes. Presence on the shelf is not
// permission: a binary in the right place with the wrong hash is refused exactly as
// one that isn't there. This is the digest-pinning rule Steward already applies to
// container images, turned on its own extensions.
//
// Neither path is configurable. A knob that redirects discovery — a flag, an
// environment variable, a config key — reintroduces everything wrong with resolving
// packs through $PATH, just through a side door. An admin who wants a different
// location recompiles or bind-mounts; the friction is the point. See
// decisions/core-and-packs.md.

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

// The shelf and the manifest. Package vars rather than consts *only* so the tests in
// this package can point them at a temp dir — deliberately not reachable from a flag
// or the environment, which is the whole point.
var (
	packShelfDir     = "/usr/libexec/steward"
	packManifestPath = "/etc/steward/packs.manifest"
)

// PackShelfDir is where pack binaries live, for the ceiling that has to create it.
func PackShelfDir() string { return packShelfDir }

// PackManifestPath is the file that says which packs may run.
func PackManifestPath() string { return packManifestPath }

var (
	selfDigestOnce sync.Once
	selfDigestVal  string
	selfDigestErr  error
)

// SelfDigest is the sha256 of the running binary, computed once.
//
// While packs are compiled in, this *is* a pack's digest: the code that would run is
// this code. When packs become separate files the digest is the pack file's, and the
// meaning of the manifest line does not change — which is why the manifest carries
// digests now, before anything is loaded from disk.
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
// path. For the out-of-process packs this is heading for, hashing a path and then
// executing the path leaves a window in which the two are different files; the fix is
// to hash and execute the same open descriptor (execveat with AT_EMPTY_PATH). Doing
// the read this way now means the exec half is the only piece still missing.
func fileDigest(path string) (string, error) {
	f, err := os.Open(path) // #nosec G304 -- our own binary, or a path from the root-owned shelf
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

// manifestEntry is one authorized pack.
type manifestEntry struct {
	Pack   string
	Digest string
}

// readManifest parses the manifest. Line-oriented and plain on purpose — like
// authorized_keys, it should be readable with `cat` by an admin who has never used
// Steward. Blank lines and # comments are ignored.
func readManifest(path string) ([]manifestEntry, error) {
	f, err := os.Open(path) // #nosec G304 -- the fixed, root-owned manifest path
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var out []manifestEntry
	sc := bufio.NewScanner(f)
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimSpace(sc.Text())
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		fields := strings.Fields(text)
		if len(fields) != 2 {
			return nil, fmt.Errorf("%s:%d: want '<pack> <sha256:...>', got %q", path, line, text)
		}
		if !strings.HasPrefix(fields[1], "sha256:") {
			return nil, fmt.Errorf("%s:%d: digest must be sha256:<hex>, got %q", path, line, fields[1])
		}
		out = append(out, manifestEntry{Pack: fields[0], Digest: fields[1]})
	}
	return out, sc.Err()
}

// renderManifest writes the file `prepare` lays down.
func renderManifest(entries []manifestEntry) string {
	var b strings.Builder
	b.WriteString("# Managed by `steward prepare`. Which packs may run on this box.\n")
	b.WriteString("# One line per pack: <pack> <sha256:...>. Root-owned; the digest is\n")
	b.WriteString("# checked before any of that pack's verbs run.\n")
	for _, e := range entries {
		fmt.Fprintf(&b, "%s %s\n", e.Pack, e.Digest)
	}
	return b.String()
}

// writeManifest lays down the manifest for the registered packs at the running
// binary's digest. Root-only in practice: the file lives under /etc.
func writeManifest() ([]manifestEntry, error) {
	digest, err := SelfDigest()
	if err != nil {
		return nil, err
	}
	entries := make([]manifestEntry, 0, len(packs))
	for _, p := range packs {
		entries = append(entries, manifestEntry{Pack: p.Name(), Digest: digest})
	}
	if err := os.MkdirAll(filepath.Dir(packManifestPath), 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(packManifestPath, []byte(renderManifest(entries)), 0o644); err != nil {
		return nil, err
	}
	return entries, nil
}

// authorizePack reports whether this pack may run, at this binary's digest. It is on
// the hot path for every packed verb, not a check that gets switched on later: a
// mechanism nobody has exercised is a mechanism nobody has tested.
//
// A missing manifest is a refusal, not a default-allow. The box either said which
// code may run or it did not.
func authorizePack(name string) error {
	entries, err := readManifest(packManifestPath)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("no pack manifest at %s — run `steward prepare`", packManifestPath)
		}
		return err
	}
	digest, err := SelfDigest()
	if err != nil {
		return fmt.Errorf("reading this binary's digest: %w", err)
	}
	for _, e := range entries {
		if e.Pack != name {
			continue
		}
		if e.Digest != digest {
			return fmt.Errorf("pack %q is authorized at %s but this binary is %s — "+
				"the manifest and the installed binary disagree; re-run `steward prepare` after an upgrade",
				name, e.Digest, digest)
		}
		return nil
	}
	return fmt.Errorf("pack %q is not in %s", name, packManifestPath)
}
