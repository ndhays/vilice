package core

// What this box is for.
//
// A machine exists to do something, and saying which costs one word at `prepare` time.
// Having said it, the box can answer "what am I for" as a fact rather than leaving a
// reader to infer it from what happens to be installed — and `deploy` on a balancer can
// refuse with a reason instead of "podman: not found".
//
// There are exactly two roles because there are exactly two things a box does here. A
// third arrives when a third is real, not for symmetry. See
// blueprint/steward/provision.md.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	// RoleHost runs applications: Podman, restic, Caddy.
	RoleHost = "host"
	// RoleBalancer fronts other boxes: Caddy alone. No container runtime.
	RoleBalancer = "balancer"
)

// Roles is every role `prepare` accepts, in the order help should list them.
var Roles = []string{RoleHost, RoleBalancer}

// rolePath is one word in the state dir, root-written and world-readable — the same
// shape as hardening.json and for the same reason: a privileged act publishes a fact the
// unprivileged observe path needs to read. Plain text, so `cat` answers the question.
func rolePath() string {
	if p := os.Getenv("STEWARD_ROLE_FILE"); p != "" {
		return p
	}
	return "/var/lib/steward/role"
}

// ValidRole reports whether s names a role, and is the single place that knows.
func ValidRole(s string) bool {
	for _, r := range Roles {
		if s == r {
			return true
		}
	}
	return false
}

// Role is what this box was prepared as, or "" if it has never been prepared. An absent
// file is not an error: it is the honest answer for a box that has not been asked yet.
func Role() string {
	b, err := os.ReadFile(rolePath()) // #nosec G304 -- steward's own state path
	if err != nil {
		return ""
	}
	role := strings.TrimSpace(string(b))
	if !ValidRole(role) {
		return ""
	}
	return role
}

// SetRole records what this box is for. Refuses to *change* an existing role: converting
// a host that is running apps into a balancer by re-running one command is exactly the
// silent surprise this design avoids, so the operator has to mean it. Re-stating the same
// role is idempotent, like the rest of prepare.
func SetRole(role string) error {
	if !ValidRole(role) {
		return fmt.Errorf("unknown role %q — expected one of %s", role, strings.Join(Roles, ", "))
	}
	if was := Role(); was != "" && was != role {
		return fmt.Errorf("this box was prepared as a %s; re-preparing it as a %s is not a "+
			"conversion this command performs. Take its apps off first, then uninstall and "+
			"prepare again", was, role)
	}
	if err := os.MkdirAll(filepath.Dir(rolePath()), 0o755); err != nil {
		return err
	}
	return os.WriteFile(rolePath(), []byte(role+"\n"), 0o644) // #nosec G306 -- a published fact, read by the observe path
}
