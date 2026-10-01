package core

// The accountability record (invariant 2): every state-changing action writes an
// entry here *before* it runs. The record is append-only and hash-chained, so a
// silent edit or deletion breaks the chain and shows. See blueprint/vilice/record.md.

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const defaultRecordPath = "/var/lib/vilice/record.log"

// tornRecordHint is the way out of an unreadable tail — a crash or a full disk mid-append
// leaves a partial line, and from then on every state-changing command refuses (it cannot
// chain onto an entry it can't read). Refusing is correct; leaving the operator without
// the recovery is not. The record is append-only, so the repair needs root.
const tornRecordHint = `A partial final line usually means a crash or a full disk mid-append.
Every action refuses until it is repaired. As root, on the box:
    chattr -a /var/lib/vilice/record.log
    # delete only the unreadable final line, keeping every entry above it
    chattr +a /var/lib/vilice/record.log
    vilice verify
Removing a *whole* entry breaks the hash chain and verify will say so — that is the
record working, not a second fault.`

// RecordPath is where the record lives. VILICE_RECORD overrides it (tests, dev).
func RecordPath() string {
	if p := os.Getenv("VILICE_RECORD"); p != "" {
		return p
	}
	return defaultRecordPath
}

// Entry is one line of the record. Hash chains it to the entry before it.
type Entry struct {
	Seq    int      `json:"seq"`
	Time   string   `json:"time"` // RFC3339, UTC
	Actor  string   `json:"actor"`
	Scope  string   `json:"scope"`
	Action string   `json:"action"`
	Args   []string `json:"args,omitempty"`
	// Digest is the sha256 of the binary that ran the action, for the verbs that
	// check it. Empty for the ones that do not (the ceiling, the rights ledger,
	// the record's own reads) and for entries written before it was recorded.
	//
	// Pack is history. Vilice once dispatched to verb packs and wrote the pack's
	// name here; that layer is gone (decisions/roles-not-packs.md), and nothing
	// sets this field any more. It stays so entries already on boxes still parse
	// and still hash to what they hashed to — the record is append-only, and a
	// reader that cannot read its own past is not a record.
	Pack     string `json:"pack,omitempty"`
	Digest   string `json:"digest,omitempty"`
	PrevHash string `json:"prev_hash"`
	Hash     string `json:"hash"`
}

// computeHash hashes every field except Hash itself, chained through PrevHash.
// Editing any field, or reordering entries, changes the result.
func (e Entry) computeHash() string {
	// Normalize an empty arg list to nil so absent/empty/nil all hash the same.
	// The stored entry uses `omitempty`, so a no-arg command writes `[]string{}`,
	// drops the field on disk, and reloads as nil on verify — without this, the
	// write-time `[]` and the verify-time `null` would hash differently and every
	// no-arg command (prepare, harden, apply-updates) would break its own chain.
	args := e.Args
	if len(args) == 0 {
		args = nil
	}
	// Two shapes, and the reason is chains already on disk. The hash covers every
	// field, so simply adding pack/digest to the payload would change the hash of
	// every entry ever written and `verify` would report a break on the first one.
	// An entry with neither therefore hashes exactly as it always did, byte for
	// byte, and only an entry that carries one commits to the wider shape. The
	// retired `pack` field stays in the wider payload for the same reason: entries
	// on real boxes carry it, and dropping it from the hash would accuse every one
	// of them of tampering. New fields must be added the same way: additively, or
	// the chain is not additive.
	var b []byte
	if e.Pack == "" && e.Digest == "" {
		payload := struct {
			Seq      int      `json:"seq"`
			Time     string   `json:"time"`
			Actor    string   `json:"actor"`
			Scope    string   `json:"scope"`
			Action   string   `json:"action"`
			Args     []string `json:"args"`
			PrevHash string   `json:"prev_hash"`
		}{e.Seq, e.Time, e.Actor, e.Scope, e.Action, args, e.PrevHash}
		b, _ = json.Marshal(payload)
	} else {
		payload := struct {
			Seq      int      `json:"seq"`
			Time     string   `json:"time"`
			Actor    string   `json:"actor"`
			Scope    string   `json:"scope"`
			Action   string   `json:"action"`
			Args     []string `json:"args"`
			Pack     string   `json:"pack"`
			Digest   string   `json:"digest"`
			PrevHash string   `json:"prev_hash"`
		}{e.Seq, e.Time, e.Actor, e.Scope, e.Action, args, e.Pack, e.Digest, e.PrevHash}
		b, _ = json.Marshal(payload)
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// lastEntry returns the final entry in the record, or found=false for a fresh one.
func lastEntry(path string) (Entry, bool, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return Entry{}, false, nil
	}
	if err != nil {
		return Entry{}, false, err
	}
	defer f.Close()

	var last Entry
	found := false
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(line), &e); err != nil {
			return Entry{}, false, fmt.Errorf("%s: entry %d is unreadable (%w).\n%s",
				path, last.Seq+1, err, tornRecordHint)
		}
		last, found = e, true
	}
	return last, found, sc.Err()
}

// Record writes one entry, chained to the current tail, then returns. It must
// succeed before the caller acts — that is what makes the action accountable.
//
// Reading the tail and appending is one critical section, held under an exclusive
// flock on the Record itself. Without it two concurrent commands both read seq N and
// both write N+1, and the chain is broken *permanently* — the Record is append-only
// (chattr +a), so nothing short of root can repair it. Vilice Console driving a box while
// an operator types is the ordinary case, not the exotic one.
// Record writes an entry that names no binary — the verbs exempt from the digest
// check, and the deny entries written when that check refuses.
func Record(actor, scope, action string, args []string) error {
	return RecordAct(actor, scope, action, args, "")
}

// RecordAct writes one entry, chained to the current tail, naming the digest of the
// binary the action ran under. digest is empty where it was not checked.
func RecordAct(actor, scope, action string, args []string, digest string) error {
	path := RecordPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	// O_APPEND|O_CREATE works on a chattr +a file; the fd is both the lock and the
	// writer, so the lock cannot be dropped between reading the tail and appending.
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return fmt.Errorf("locking the record: %w", err)
	}
	// Released with the fd on close; an unlock here would race the deferred write.

	last, found, err := lastEntry(path)
	if err != nil {
		return err
	}
	e := Entry{
		Seq:    1,
		Time:   time.Now().UTC().Format(time.RFC3339),
		Actor:  actor,
		Scope:  scope,
		Action: action,
		Args:   args,
		Digest: digest,
	}
	if found {
		e.Seq = last.Seq + 1
		e.PrevHash = last.Hash
	}
	e.Hash = e.computeHash()

	b, err := json.Marshal(e)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

// verifyChain walks the record and reports the first break: a wrong sequence, a
// broken prev-hash link, or an entry whose hash no longer matches its contents.
func verifyChain(path string) error {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil // an empty record is a valid record
	}
	if err != nil {
		return err
	}
	defer f.Close()

	prevHash := ""
	prevSeq := 0
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(line), &e); err != nil {
			return fmt.Errorf("entry after seq %d: %w", prevSeq, err)
		}
		if e.Seq != prevSeq+1 {
			return fmt.Errorf("seq %d out of order (expected %d)", e.Seq, prevSeq+1)
		}
		if e.PrevHash != prevHash {
			return fmt.Errorf("seq %d: broken chain (prev_hash mismatch)", e.Seq)
		}
		if e.computeHash() != e.Hash {
			return fmt.Errorf("seq %d: hash does not match contents (tampered)", e.Seq)
		}
		prevHash, prevSeq = e.Hash, e.Seq
	}
	return sc.Err()
}

// verifyCmd is the observe-scope payoff of the chain: anyone with read access can
// check that no entry was edited, reordered, or removed. A read, so it is not itself
// recorded. See blueprint/vilice/record.md.
func verifyCmd(_ []string) Result {
	path := RecordPath()
	if err := verifyChain(path); err != nil {
		return Result{Code: "record_broken", Message: err.Error(), Data: map[string]any{"intact": false}}
	}
	last, found, err := lastEntry(path)
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	n := 0
	if found {
		n = last.Seq
	}
	noun := "entries"
	if n == 1 {
		noun = "entry"
	}
	return Result{
		Code:    "ok",
		Message: fmt.Sprintf("record intact — %d %s verified", n, noun),
		Data:    map[string]any{"intact": true, "entries": n},
	}
}

// readEntries returns every entry in the record, oldest first. A missing record
// is an empty record, not an error.
func readEntries(path string) ([]Entry, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return []Entry{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()

	entries := []Entry{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(line), &e); err != nil {
			return nil, fmt.Errorf("record line after seq %d: %w", len(entries), err)
		}
		entries = append(entries, e)
	}
	return entries, sc.Err()
}

// recordCmd (observe) dumps the accountable record itself — the entries plus the
// chain-integrity check — so a reader (Vilice Console) can show the witnessed history
// and prove it is unbroken. A read; not itself recorded.
func recordCmd(_ []string) Result {
	path := RecordPath()
	entries, err := readEntries(path)
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	intact, integrity := true, "intact"
	if verr := verifyChain(path); verr != nil {
		intact, integrity = false, verr.Error()
	}
	state := "intact"
	if !intact {
		state = "BROKEN"
	}
	noun := "entries"
	if len(entries) == 1 {
		noun = "entry"
	}
	return Result{
		Code:    "ok",
		Message: fmt.Sprintf("%d %s, chain %s", len(entries), noun, state),
		Data: map[string]any{
			"entries": entries, "count": len(entries), "intact": intact, "integrity": integrity,
		},
	}
}
