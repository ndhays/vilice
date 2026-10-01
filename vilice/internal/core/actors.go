package core

// `actors` (observe): read the rights ledger back out.
//
// `authorize` and `revoke` write authorized_keys; until now nothing read it for
// display, so the one file that *is* the list of who may act on this box could only
// be seen by getting a shell on the box — which no scoped key grants. A ledger nobody
// can read is a ledger nobody can check, so the read is a named verb like everything
// else, at observe scope, holding no privilege.
//
// It reports two things, and the second matters as much as the first: the grants
// Vilice wrote, and any line it did not. A hand-added key with no forced command is a
// way onto the box that skips the door entirely, and the only place that can ever
// become visible is here.

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"os"
	"sort"
	"strings"
)

// Actor is one line of the rights ledger.
type Actor struct {
	Client string `json:"client"`
	Scope  string `json:"scope"`
	// KeyType and Fingerprint identify the key without reproducing it.
	KeyType     string `json:"key_type"`
	Fingerprint string `json:"fingerprint"`
	Comment     string `json:"comment,omitempty"`
	// Command is the forced command the line pins. Reported so an operator can see
	// the ceiling for themselves rather than trusting this parse of it.
	Command string `json:"command"`
	// Pinned is false for a line that is not a Vilice grant — no forced command, or
	// one this binary did not write. Such a line is a way in that skips the gate.
	Pinned bool `json:"pinned"`
	// Raw is the whole line, for an unpinned entry that cannot be described any
	// other way.
	Raw string `json:"raw,omitempty"`
}

func actorsCmd(_ []string) Result {
	path, err := AuthorizedKeysPath()
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	data, err := os.ReadFile(path) // #nosec G304 -- vilice's own ledger path
	if os.IsNotExist(err) {
		return Result{Code: "ok", Message: "no scoped keys — nobody can reach this box through Vilice",
			Data: map[string]any{"path": path, "actors": []Actor{}}}
	}
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}

	actors := parseLedger(string(data))
	unpinned := 0
	for _, a := range actors {
		if !a.Pinned {
			unpinned++
		}
	}
	res := Result{Code: "ok", Message: renderActors(actors, unpinned),
		Data: map[string]any{"path": path, "actors": actors, "unpinned": unpinned}}
	return res
}

// parseLedger turns authorized_keys into actors. Pure, so the shape of a hostile or
// hand-edited file is testable without one on disk.
func parseLedger(data string) []Actor {
	var out []Actor
	for _, line := range NonEmptyLines(data) {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, parseLedgerLine(line))
	}
	sort.SliceStable(out, func(i, j int) bool {
		// Unpinned lines first: they are the ones that need attention.
		if out[i].Pinned != out[j].Pinned {
			return !out[i].Pinned
		}
		return out[i].Client < out[j].Client
	})
	return out
}

func parseLedgerLine(line string) Actor {
	const prefix = `command="`
	if !strings.HasPrefix(line, prefix) {
		return Actor{Pinned: false, Raw: line, KeyType: keyType(line), Fingerprint: fingerprint(line)}
	}
	rest := line[len(prefix):]
	end := strings.Index(rest, `"`)
	if end < 0 {
		return Actor{Pinned: false, Raw: line}
	}
	command := rest[:end]
	// After the closing quote come the remaining options (`,restrict`), then a space,
	// then the key itself.
	after := rest[end+1:]
	sp := strings.Index(after, " ")
	if sp < 0 {
		return Actor{Pinned: false, Raw: line}
	}
	key := strings.TrimSpace(after[sp+1:])

	a := Actor{
		Command:     command,
		Client:      flagValue(command, "--client"),
		Scope:       flagValue(command, "--scope"),
		KeyType:     keyType(key),
		Fingerprint: fingerprint(key),
		Comment:     keyComment(key),
	}
	// A forced command that isn't `_exec` with a client and a scope is not a grant
	// this binary would write, whatever else it is.
	a.Pinned = strings.Contains(command, " _exec ") && a.Client != "" && a.Scope != ""
	if !a.Pinned {
		a.Raw = line
	}
	return a
}

// flagValue pulls `--name <value>` out of the forced command.
func flagValue(command, name string) string {
	fields := strings.Fields(command)
	for i, f := range fields {
		if f == name && i+1 < len(fields) {
			return fields[i+1]
		}
	}
	return ""
}

func keyType(key string) string {
	fields := strings.Fields(key)
	if len(fields) > 0 && strings.HasPrefix(fields[0], "ssh-") || (len(fields) > 0 && strings.HasPrefix(fields[0], "ecdsa-")) {
		return fields[0]
	}
	return ""
}

func keyComment(key string) string {
	fields := strings.Fields(key)
	if len(fields) >= 3 {
		return strings.Join(fields[2:], " ")
	}
	return ""
}

// fingerprint is the OpenSSH SHA256 fingerprint of a public key — the same string
// `ssh-keygen -lf` prints, so an operator can compare it against the key in their
// hand without trusting us to have copied it correctly.
func fingerprint(key string) string {
	fields := strings.Fields(key)
	if len(fields) < 2 {
		return ""
	}
	blob, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(blob)
	return "SHA256:" + strings.TrimRight(base64.StdEncoding.EncodeToString(sum[:]), "=")
}

func renderActors(actors []Actor, unpinned int) string {
	if len(actors) == 0 {
		return "no scoped keys — nobody can reach this box through Vilice"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%d actor(s) may act on this box:\n\n", len(actors)-unpinned)
	for _, a := range actors {
		if !a.Pinned {
			continue
		}
		fmt.Fprintf(&b, "  %-16s %-8s %s %s\n", a.Client, a.Scope, a.KeyType, a.Fingerprint)
	}
	if unpinned > 0 {
		fmt.Fprintf(&b, "\n  %d line(s) in the ledger are NOT Vilice grants — they carry no\n", unpinned)
		b.WriteString("  forced command, so a holder reaches the box without passing the gate:\n")
		for _, a := range actors {
			if a.Pinned {
				continue
			}
			label := a.Fingerprint
			if label == "" {
				label = "unreadable"
			}
			fmt.Fprintf(&b, "    %s %s\n", a.KeyType, label)
		}
	}
	return strings.TrimRight(b.String(), "\n")
}
