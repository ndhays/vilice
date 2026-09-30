package app

// `status` (observe): a machine summary plus the apps on the box and their state.
// Machine metrics come from /proc and statfs; apps come from Podman when present.
// See blueprint/steward/record.md (reads are observe-scoped, zero-privilege).

import (
	"steward/internal/core"

	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type machineStatus struct {
	MachineID      string  `json:"machine_id,omitempty"` // stable per-install id (/etc/machine-id)
	Hostname       string  `json:"hostname"`
	UptimeSec      int64   `json:"uptime_sec"`
	Load1          float64 `json:"load1"`
	MemTotalKB     int64   `json:"mem_total_kb"`
	MemAvailableKB int64   `json:"mem_available_kb"`
	DiskTotalBytes uint64  `json:"disk_total_bytes"`
	DiskFreeBytes  uint64  `json:"disk_free_bytes"`
}

type appStatus struct {
	Name  string `json:"name"`            // the app name you pass to commands (no color suffix)
	Color string `json:"color,omitempty"` // blue/green color of the running container ("a"|"b")
	Image string `json:"image"`
	State string `json:"state"`
}

func statusCmd(args []string) core.Result {
	m := collectMachine()
	apps, note := collectApps()

	data := map[string]any{"machine": m, "apps": apps}
	if note != "" {
		data["apps_note"] = note
	}
	msg := renderStatus(m, apps, note)
	// What this box was prepared as. A reader (and the console) shapes what it offers
	// around this rather than around what happens to be installed.
	if role := core.Role(); role != "" {
		data["role"] = role
		msg += "\n\nRole: " + role
	}
	// Surface the hardening fact the privileged side published. Observe can't compute
	// posture (that needs root) — it only reads what harden wrote. **Always rendered**:
	// an absent file means the box was never hardened, and omitting the section
	// entirely would read as "nothing to report" rather than "not hardened". Absence
	// is a fact here, the same way an unreachable box reports unknown and not none.
	if p, ok := collectHardening(); ok {
		data["hardening"] = p
		msg += "\n\n" + renderHardeningLine(p)
	} else {
		data["hardening_known"] = false
		msg += "\n\nSecurity: not hardened — no posture has been published. Run `steward harden`."
	}
	// The automatic-maintenance window (when security patches + any reboot land) and the
	// updates pending now — so a reader can show the schedule and an "apply now". Both
	// best-effort; absent when apt can't be read.
	if mw := collectMaintenance(); mw != nil {
		data["maintenance"] = mw
	}
	if u := collectUpdates(); u != nil {
		data["updates"] = u
	}
	// When each app and the record last backed up, as `backup` noted it — never a live
	// query of the repo (see backups.go).
	data["backups"] = collectBackups()
	// The certificate each served hostname actually hands out (see certs.go).
	if certs := collectCerts(); certs != nil {
		data["certs"] = certs
	}
	// Make the box's standing registry credentials legible — host + username, never the
	// secret. A credential nothing surfaces is ambient authority. See registry.go.
	if regs := loggedInRegistries(); len(regs) > 0 {
		data["registries"] = regs
		msg += "\n\n" + renderRegistries(regs)
	}
	// What this box fronts for *other* boxes, read off the fragment `route` wrote. This
	// is the reality half of the edge: a control plane can compare it against the table
	// it believes it sent, and see the gap rather than assume there isn't one.
	if r := currentRoutes(); len(r) > 0 {
		data["routes"] = r
		msg += "\n\nFronting: " + strings.Join(r, ", ")
	}
	return core.Result{Code: "ok", Message: msg, Data: data}
}

// collectHardening reads the published hardening fact. Absent file → ok=false (the box
// was never checked) — true-or-absent: observe reports only what it can know.
func collectHardening() (core.HardeningPosture, bool) {
	b, err := os.ReadFile(core.HardeningPath()) // #nosec G304 -- steward's own configured status-lane path
	if err != nil {
		return core.HardeningPosture{}, false
	}
	p, err := core.ParseHardening(b)
	if err != nil {
		return core.HardeningPosture{}, false
	}
	return p, true
}

// renderHardeningLine is the one-line hardening summary in `status` text output.
func renderHardeningLine(p core.HardeningPosture) string {
	state := "hardened"
	if d := p.Drift(); len(d) > 0 {
		state = "drift: " + strings.Join(d, "; ")
	}
	when := p.CheckedAt
	if when == "" {
		when = "unknown"
	}
	return fmt.Sprintf("hardening  %s (checked %s)", state, when)
}

// --- snapshot: the status time-series ---
//
// `snapshot` (system scope) appends one timestamped sample of machine + app state to
// a status log. It is the recorder's pulse — something runs it on a cadence, not a
// person. Kept separate from the audit record (audit.go): that chain is for actions;
// this is for state over time. Both together are the "dump" a lens reads.

type snapshotPoint struct {
	Time     string        `json:"time"`
	Machine  machineStatus `json:"machine"`
	Apps     []appStatus   `json:"apps"`
	AppsNote string        `json:"apps_note,omitempty"`
}

func statusLogPath() string {
	if p := os.Getenv("STEWARD_STATUS"); p != "" {
		return p
	}
	return "/var/lib/steward/status.jsonl"
}

func snapshotCmd(args []string) core.Result {
	apps, note := collectApps()
	pt := snapshotPoint{
		Time:     time.Now().UTC().Format(time.RFC3339),
		Machine:  collectMachine(),
		Apps:     apps,
		AppsNote: note,
	}
	b, err := json.Marshal(pt)
	if err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	path := statusLogPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o640)
	if err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	defer f.Close()
	if _, err := f.Write(append(b, '\n')); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	return core.OK("snapshot written to " + path)
}

func collectMachine() machineStatus {
	var m machineStatus
	m.Hostname, _ = os.Hostname()
	// Stable per-install identity, so a reader (Steward Console) can recognize the box
	// it is itself running on. Best-effort: absent on the rare host without it.
	if b, err := os.ReadFile("/etc/machine-id"); err == nil {
		m.MachineID = strings.TrimSpace(string(b))
	}
	if b, err := os.ReadFile("/proc/uptime"); err == nil {
		m.UptimeSec = parseUptime(string(b))
	}
	if b, err := os.ReadFile("/proc/loadavg"); err == nil {
		m.Load1 = parseLoadavg(string(b))
	}
	if b, err := os.ReadFile("/proc/meminfo"); err == nil {
		m.MemTotalKB, m.MemAvailableKB = parseMeminfo(string(b))
	}
	var st syscall.Statfs_t
	if err := syscall.Statfs("/", &st); err == nil {
		m.DiskTotalBytes = st.Blocks * uint64(st.Bsize) // #nosec G115 -- statfs block size is a small positive value
		m.DiskFreeBytes = st.Bavail * uint64(st.Bsize)  // #nosec G115 -- statfs block size is a small positive value
	}
	return m
}

// collectUpdates lists available package updates, best-effort and unprivileged: it
// simulates an apt upgrade and reads the "Inst" lines. A package is counted as security
// when its source suite mentions security. nil when apt is absent or the query fails —
// observe reports only what it can know, so the apply-updates act stays hidden then.
func collectUpdates() map[string]any {
	out, err := exec.Command("apt-get", "-s", "-q", "-o", "Debug::NoLocking=true", "upgrade").CombinedOutput()
	if err != nil {
		return nil
	}
	count := 0
	var security []string
	for _, ln := range strings.Split(string(out), "\n") {
		if !strings.HasPrefix(ln, "Inst ") {
			continue
		}
		count++
		fields := strings.Fields(ln)
		if len(fields) < 2 {
			continue
		}
		if strings.Contains(strings.ToLower(ln), "security") {
			security = append(security, fields[1])
		}
	}
	if count == 0 {
		return nil
	}
	return map[string]any{"count": count, "security": len(security), "packages": security}
}

// collectMaintenance reads the box's automatic-maintenance window — the unattended-upgrades
// reboot time `harden` sets. Best-effort + unprivileged (`apt-config dump` is world-readable);
// nil when no window is configured. Lets a reader show "maintenance at HH:MM" and a
// reschedule, rather than a package list.
func collectMaintenance() map[string]any {
	out, err := exec.Command("apt-config", "dump").CombinedOutput()
	if err != nil {
		return nil
	}
	return parseMaintenance(string(out))
}

// parseMaintenance pulls the reboot time + auto-reboot flag from `apt-config dump` output.
// nil when no reboot time is set (nothing to report).
func parseMaintenance(dump string) map[string]any {
	rebootAt := aptConfigValue(dump, "Unattended-Upgrade::Automatic-Reboot-Time")
	if rebootAt == "" {
		return nil
	}
	auto := strings.EqualFold(aptConfigValue(dump, "Unattended-Upgrade::Automatic-Reboot"), "true")
	return map[string]any{"reboot_time": rebootAt, "auto_reboot": auto}
}

// aptConfigValue reads the quoted value for a key from `apt-config dump` lines, which read
// `Key::Path "value";`. The trailing space in the match keeps "Automatic-Reboot" from also
// matching "Automatic-Reboot-Time".
func aptConfigValue(dump, key string) string {
	for _, ln := range strings.Split(dump, "\n") {
		ln = strings.TrimSpace(ln)
		if !strings.HasPrefix(ln, key+" ") {
			continue
		}
		if i := strings.IndexByte(ln, '"'); i >= 0 {
			if j := strings.IndexByte(ln[i+1:], '"'); j >= 0 {
				return ln[i+1 : i+1+j]
			}
		}
	}
	return ""
}

// collectApps lists containers via Podman. A missing Podman is not an error here —
// it just means no apps yet; the note says so.
func collectApps() ([]appStatus, string) {
	if _, err := exec.LookPath("podman"); err != nil {
		return nil, "podman not found"
	}
	// Through the user-context seam so it reads the steward user's rootless containers
	// (correct XDG_RUNTIME_DIR / cwd) — the snapshot timer runs as the steward user.
	out, err := podmanOutput("ps", "-a", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}")
	if err != nil {
		return nil, "podman ps failed: " + err.Error()
	}
	return parsePodmanPS(out), ""
}

// --- pure parsers (tested) ---

func parseUptime(s string) int64 {
	f := strings.Fields(s)
	if len(f) == 0 {
		return 0
	}
	v, _ := strconv.ParseFloat(f[0], 64)
	return int64(v)
}

func parseLoadavg(s string) float64 {
	f := strings.Fields(s)
	if len(f) == 0 {
		return 0
	}
	v, _ := strconv.ParseFloat(f[0], 64)
	return v
}

func parseMeminfo(s string) (total, available int64) {
	for _, ln := range strings.Split(s, "\n") {
		f := strings.Fields(ln)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseInt(f[1], 10, 64) // value is in kB
		switch f[0] {
		case "MemTotal:":
			total = v
		case "MemAvailable:":
			available = v
		}
	}
	return total, available
}

func parsePodmanPS(s string) []appStatus {
	var apps []appStatus
	for _, ln := range strings.Split(strings.TrimSpace(s), "\n") {
		if strings.TrimSpace(ln) == "" {
			continue
		}
		f := strings.SplitN(ln, "\t", 3)
		name, color := splitColor(f[0])
		a := appStatus{Name: name, Color: color}
		if len(f) > 1 {
			a.Image = f[1]
		}
		if len(f) > 2 {
			a.State = f[2]
		}
		apps = append(apps, a)
	}
	return apps
}

// splitColor separates a Podman container name (`<app>-<color>`) into the app name —
// what every command takes — and its blue/green color. A name without an `-a`/`-b`
// suffix is returned unchanged (color empty).
func splitColor(container string) (app, color string) {
	if n := len(container); n > 2 && container[n-2] == '-' && (container[n-1] == 'a' || container[n-1] == 'b') {
		return container[:n-2], container[n-1:]
	}
	return container, ""
}

// --- human rendering ---

func renderStatus(m machineStatus, apps []appStatus, note string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "host    %s\n", m.Hostname)
	fmt.Fprintf(&b, "uptime  %s\n", humanDuration(m.UptimeSec))
	fmt.Fprintf(&b, "load    %.2f\n", m.Load1)
	if m.MemTotalKB > 0 {
		usedPct := 100 * (m.MemTotalKB - m.MemAvailableKB) / m.MemTotalKB
		fmt.Fprintf(&b, "memory  %d%% used of %s\n", usedPct, humanBytes(uint64(m.MemTotalKB)*1024))
	}
	if m.DiskTotalBytes > 0 {
		usedPct := 100 * (m.DiskTotalBytes - m.DiskFreeBytes) / m.DiskTotalBytes
		fmt.Fprintf(&b, "disk    %d%% used of %s\n", usedPct, humanBytes(m.DiskTotalBytes))
	}

	b.WriteString("\napps\n")
	if len(apps) == 0 {
		reason := "none"
		if note != "" {
			reason = note
		}
		fmt.Fprintf(&b, "  (%s)\n", reason)
		return strings.TrimRight(b.String(), "\n")
	}
	for _, a := range apps {
		name := a.Name
		if a.Color != "" {
			name += " (" + a.Color + ")"
		}
		fmt.Fprintf(&b, "  %-16s %-28s %s\n", name, a.Image, a.State)
	}
	return strings.TrimRight(b.String(), "\n")
}

func humanDuration(sec int64) string {
	d := sec / 86400
	h := (sec % 86400) / 3600
	mn := (sec % 3600) / 60
	switch {
	case d > 0:
		return fmt.Sprintf("%dd %dh %dm", d, h, mn)
	case h > 0:
		return fmt.Sprintf("%dh %dm", h, mn)
	default:
		return fmt.Sprintf("%dm", mn)
	}
}

func humanBytes(n uint64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%dB", n)
	}
	div, exp := uint64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f%cB", float64(n)/float64(div), "KMGTPE"[exp])
}
