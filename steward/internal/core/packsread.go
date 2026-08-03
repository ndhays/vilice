package core

// `packs` (observe): read the manifest back out.
//
// The companion to `actors`. That one answers *who may act on this box*; this one
// answers *what code may run on it*. Both are facts the box holds and nothing else
// should copy — a control plane that stored its own list of either would eventually
// disagree with the machine, and be believed.
//
// It reports three states, and the two unhappy ones are the point. A pack the
// manifest authorizes but this binary does not carry means the manifest is stale —
// nothing runs, and the reason is not obvious from a failure. A pack the binary
// carries but the manifest does not authorize is code sitting inert on the box.
// Neither is visible anywhere else.

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

// PackState is what the manifest and the binary jointly say about one pack.
type PackState struct {
	Name   string `json:"name"`
	Digest string `json:"digest,omitempty"`
	// State is "active" (authorized and carried), "stale" (authorized at a digest
	// this binary is not), "missing" (authorized but not carried), or
	// "unauthorized" (carried but not in the manifest).
	State string `json:"state"`
	Note  string `json:"note,omitempty"`
}

const (
	packActive       = "active"
	packStale        = "stale"
	packMissing      = "missing"
	packUnauthorized = "unauthorized"
)

func packsCmd(_ []string) Result {
	self, digestErr := SelfDigest()
	// A missing manifest is a real state, not a failure: a box that authorized
	// nothing runs the core and nothing else, and should say so.
	entries, err := readManifest(packManifestPath)
	if err != nil && !os.IsNotExist(err) {
		return Result{Code: "io_error", Message: err.Error()}
	}

	states := packStates(entries, registeredNames(), self, digestErr == nil)
	return Result{Code: "ok", Message: renderPacks(states, packManifestPath),
		Data: map[string]any{"manifest": packManifestPath, "self_digest": self, "packs": states}}
}

func registeredNames() []string {
	names := make([]string, 0, len(packs))
	for _, p := range packs {
		names = append(names, p.Name())
	}
	return names
}

// packStates joins what the manifest authorizes against what this binary carries.
// Pure, so every combination is testable without a manifest on disk.
func packStates(entries []manifestEntry, carried []string, selfDigest string, haveDigest bool) []PackState {
	inBinary := map[string]bool{}
	for _, n := range carried {
		inBinary[n] = true
	}
	var out []PackState
	authorized := map[string]bool{}
	for _, e := range entries {
		authorized[e.Pack] = true
		st := PackState{Name: e.Pack, Digest: e.Digest}
		switch {
		case !inBinary[e.Pack]:
			st.State = packMissing
			st.Note = "authorized, but this binary does not carry it — nothing to run"
		case haveDigest && e.Digest != selfDigest:
			st.State = packStale
			st.Note = "authorized at a different digest than this binary — re-run `steward prepare`"
		default:
			st.State = packActive
		}
		out = append(out, st)
	}
	for _, n := range carried {
		if !authorized[n] {
			out = append(out, PackState{Name: n, State: packUnauthorized,
				Note: "carried by this binary but not in the manifest — its verbs are refused"})
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		// Anything wrong first; it is what a reader is here for.
		if (out[i].State == packActive) != (out[j].State == packActive) {
			return out[j].State == packActive
		}
		return out[i].Name < out[j].Name
	})
	return out
}

func renderPacks(states []PackState, manifest string) string {
	if len(states) == 0 {
		return "no packs authorized — this box runs the core and nothing else\n  " + manifest
	}
	var b strings.Builder
	for _, s := range states {
		fmt.Fprintf(&b, "  %-16s %-13s %s\n", s.Name, s.State, s.Digest)
		if s.Note != "" {
			fmt.Fprintf(&b, "  %-16s %s\n", "", s.Note)
		}
	}
	fmt.Fprintf(&b, "\n  %s", manifest)
	return strings.TrimRight(b.String(), "\n")
}
