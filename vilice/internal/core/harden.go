package core

// `harden` runs a self-contained, generic Ubuntu hardening unit (the harden/ folder).
// Those scripts know nothing about vilice — no _vilice user, no record, no Podman.
// vilice just carries them embedded and runs them in order. Optional and standalone:
// the typical first step on a fresh box, or skipped entirely. See blueprint/vilice/
// provision.md (harden is kept separate from prepare on purpose).

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

//go:embed harden
var hardenFS embed.FS

func hardenCmd(args []string) Result {
	// `--check` is a read: assert the posture, change nothing. Routed here (and kept
	// off the record by dispatch's recordable()) so it works before prepare lays the
	// floor, the same way `verify` is a read that isn't recorded.
	if hasFlag(args, "--check") {
		return hardenCheck()
	}

	if os.Geteuid() != 0 {
		return Result{Code: "not_root", Message: "harden must run as root"}
	}

	dir, err := os.MkdirTemp("", "vilice-harden-")
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	defer os.RemoveAll(dir)

	if err := extractEmbed(hardenFS, "harden", dir); err != nil {
		return Result{Code: "io_error", Message: "extracting harden steps: " + err.Error()}
	}
	steps, err := stepScripts(dir)
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	if len(steps) == 0 {
		return Result{Code: "harden_failed", Message: "no harden steps found"}
	}

	for _, s := range steps {
		fmt.Printf("\n=== %s ===\n", filepath.Base(s))
		c := exec.Command("bash", s) // #nosec G204 -- s is a path to one of our own embedded harden scripts, not user input
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		c.Env = append(os.Environ(), "DEBIAN_FRONTEND=noninteractive")
		if err := c.Run(); err != nil {
			return Result{Code: "harden_failed", Retryable: true,
				Message: fmt.Sprintf("%s: %v", filepath.Base(s), err)}
		}
	}

	// Publish the resulting posture so observe (Vilice Console) can read it. Best-effort:
	// the box is hardened either way; a residency failure shouldn't fail the apply.
	if p, err := postureFromDir(dir); err == nil {
		_ = publishHardening(&p)
	}
	return OK(fmt.Sprintf("box hardened — %s", osPretty()))
}

// HardeningPosture is the published hardening fact: the booleans check.sh reports,
// plus when it was checked and on which box. Written by harden/`harden --check` (root),
// read by status (the unprivileged _vilice user) — the privilege bridge. The privileged
// side writes the fact; observe only ever reads it. See decisions/security-audit.md.
type HardeningPosture struct {
	SSHRootLoginDisabled bool   `json:"ssh_root_login_disabled"`
	PasswordAuthDisabled bool   `json:"password_auth_disabled"`
	FirewallActive       bool   `json:"firewall_active"`
	Fail2banActive       bool   `json:"fail2ban_active"`
	UnattendedUpgrades   bool   `json:"unattended_upgrades"`
	OpenPorts            string `json:"open_ports,omitempty"`
	CheckedAt            string `json:"checked_at,omitempty"`
	MachineID            string `json:"machine_id,omitempty"`
}

// drift lists the hardening properties that are NOT in place, in plain language.
// Empty means fully hardened.
func (p HardeningPosture) Drift() []string {
	var d []string
	if !p.SSHRootLoginDisabled {
		d = append(d, "root SSH login enabled")
	}
	if !p.PasswordAuthDisabled {
		d = append(d, "password auth enabled")
	}
	if !p.FirewallActive {
		d = append(d, "firewall inactive")
	}
	if !p.Fail2banActive {
		d = append(d, "fail2ban not running")
	}
	if !p.UnattendedUpgrades {
		d = append(d, "unattended upgrades off")
	}
	return d
}

func (p HardeningPosture) Hardened() bool { return len(p.Drift()) == 0 }

// hardenCheck asserts the box's hardening posture and publishes it. A read — needs root
// for an authoritative `sshd -T`/`ufw` look, returns `hardening_drift` (exit 1) if
// anything regressed, the way `verify` returns `record_broken`.
func hardenCheck() Result {
	if os.Geteuid() != 0 {
		return Result{Code: "not_root", Message: "harden --check must run as root (it reads sshd -T and ufw)"}
	}
	p, err := postureFromEmbed()
	if err != nil {
		return Result{Code: "harden_check_failed", Retryable: true, Message: err.Error()}
	}
	msg := renderHardening(p)
	if err := publishHardening(&p); err != nil {
		msg += "\n(could not publish hardening.json: " + err.Error() + ")"
	}
	data := map[string]any{"hardening": p}
	if p.Hardened() {
		return Result{Code: "ok", Message: msg, Data: data}
	}
	return Result{Code: "hardening_drift", Message: msg, Data: data}
}

// postureFromEmbed extracts the harden tree to a temp dir and runs check.sh.
func postureFromEmbed() (HardeningPosture, error) {
	dir, err := os.MkdirTemp("", "vilice-check-")
	if err != nil {
		return HardeningPosture{}, err
	}
	defer os.RemoveAll(dir)
	if err := extractEmbed(hardenFS, "harden", dir); err != nil {
		return HardeningPosture{}, fmt.Errorf("extracting harden steps: %w", err)
	}
	return postureFromDir(dir)
}

// postureFromDir runs the embedded check.sh from an already-extracted dir and parses it.
func postureFromDir(dir string) (HardeningPosture, error) {
	out, err := exec.Command("bash", filepath.Join(dir, "check.sh")).Output() // #nosec G204 -- our own embedded posture script
	if err != nil {
		return HardeningPosture{}, fmt.Errorf("check.sh: %w", err)
	}
	return ParseHardening(out)
}

// ParseHardening decodes check.sh's JSON line into the posture. Pure (tested).
func ParseHardening(b []byte) (HardeningPosture, error) {
	var p HardeningPosture
	if err := json.Unmarshal(b, &p); err != nil {
		return HardeningPosture{}, fmt.Errorf("parsing hardening posture: %w", err)
	}
	return p, nil
}

// HardeningPath is where harden publishes the posture fact. VILICE_HARDENING overrides
// it (tests, dev).
func HardeningPath() string {
	if p := os.Getenv("VILICE_HARDENING"); p != "" {
		return p
	}
	return "/var/lib/vilice/hardening.json"
}

// publishHardening stamps the posture (when + which box) and writes it to the status
// lane, where the unprivileged observe path can read it. Mode 0644: root writes it,
// the _vilice user reads it.
func publishHardening(p *HardeningPosture) error {
	p.CheckedAt = time.Now().UTC().Format(time.RFC3339)
	if b, err := os.ReadFile("/etc/machine-id"); err == nil {
		p.MachineID = strings.TrimSpace(string(b))
	}
	b, err := json.Marshal(p)
	if err != nil {
		return err
	}
	path := HardeningPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

// renderHardening is the human posture report for `harden --check`.
func renderHardening(p HardeningPosture) string {
	mark := func(ok bool) string {
		if ok {
			return "OK  "
		}
		return "FAIL"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s root SSH login disabled\n", mark(p.SSHRootLoginDisabled))
	fmt.Fprintf(&b, "%s password auth disabled\n", mark(p.PasswordAuthDisabled))
	fmt.Fprintf(&b, "%s firewall active\n", mark(p.FirewallActive))
	fmt.Fprintf(&b, "%s fail2ban running\n", mark(p.Fail2banActive))
	fmt.Fprintf(&b, "%s unattended upgrades\n", mark(p.UnattendedUpgrades))
	if d := p.Drift(); len(d) > 0 {
		fmt.Fprintf(&b, "\ndrift: %s", strings.Join(d, "; "))
	} else {
		b.WriteString("\nhardened")
	}
	return b.String()
}

// extractEmbed writes an embedded tree to dest, preserving structure. Scripts land
// executable; the temp dir is private (0700).
func extractEmbed(efs embed.FS, root, dest string) error {
	return fs.WalkDir(efs, root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return err
		}
		target := filepath.Join(dest, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o700)
		}
		b, err := efs.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(target, b, 0o755)
	})
}

// stepScripts returns the NN-*.sh step files in run order. common.sh (no digit
// prefix) is deliberately excluded — it's sourced by the steps, not run.
func stepScripts(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var steps []string
	for _, e := range entries {
		n := e.Name()
		if !e.IsDir() && len(n) > 0 && n[0] >= '0' && n[0] <= '9' && strings.HasSuffix(n, ".sh") {
			steps = append(steps, filepath.Join(dir, n))
		}
	}
	sort.Strings(steps)
	return steps, nil
}
