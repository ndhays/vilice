package app

// The substrate this layer runs on, and installing it.
//
// This is the prepare half of the core/app line. It lives here rather than in the
// ceiling because Podman, Caddy and restic are *this layer's* dependencies, not the
// box's: a balancer needs none of them. The core lays the accountability floor and
// then asks this layer to make itself workable.
//
// The names are the substrate's, not the layer's — this layer promises apps that
// deploy, route and restore; these three are today's way of keeping that promise.

import (
	"fmt"
	"path/filepath"

	"steward/internal/core"
)

// A tool is one piece of substrate: what an operator calls it, the step that puts it
// on the box, and how it states its version. `prepare` installs this list and reports
// it; `uninstall` names the same list on the way out. One list, so what a role gets
// and what the box says it has cannot drift apart.
type tool struct {
	name        string
	install     func() error
	versionArgs []string
}

// tools is the substrate a role gets, in the order `prepare` installs it. A balancer
// terminates and forwards; it runs no containers and keeps no backups, so it gets
// Caddy and nothing else. A box with no role yet reads as a host — the wider set, and
// the caller that has to be right about a particular box checks what is installed.
func tools(role string) []tool {
	caddy := tool{"caddy", installCaddy, []string{"version"}}
	if role == core.RoleBalancer {
		return []tool{caddy}
	}
	return []tool{
		{"podman", installPodman, []string{"--version"}},
		caddy,
		{"restic", installRestic, []string{"version"}},
	}
}

// Substrate is what the operator is consenting to when `prepare` asks. The apt
// package names, which are not quite the tool names: `podman` wants `uidmap` with it,
// and Caddy comes from its own repo, so apt cannot simulate it until that repo exists.
func (Layer) Substrate(role string) core.Substrate {
	if role == core.RoleBalancer {
		return core.Substrate{Note: "Caddy from its official apt repo"}
	}
	return core.Substrate{
		Packages: []string{"podman", "uidmap", "restic"},
		Note:     "plus Caddy from its official apt repo",
	}
}

// Prepare installs the substrate and configures Caddy's routing. Idempotent: each
// step checks before acting, so a second `prepare` converges rather than doubling up.
func (Layer) Prepare(role string) error {
	for _, t := range tools(role) {
		fmt.Printf("\n=== install %s ===\n", t.name)
		if err := t.install(); err != nil {
			return fmt.Errorf("install %s: %w", t.name, err)
		}
	}
	fmt.Println("\n=== configure caddy routing ===")
	if err := configureCaddy(); err != nil {
		return fmt.Errorf("configure caddy routing: %w", err)
	}
	// This layer reports its own substrate, because it is what depends on it — and
	// reports the role's substrate, so a balancer does not print a Podman line.
	fmt.Println()
	for _, t := range tools(role) {
		fmt.Printf("  %-9s %s\n", t.name+":", core.CmdFirstLine(t.name, t.versionArgs...))
	}
	return nil
}

func installPodman() error {
	if core.Have("podman") {
		fmt.Println("podman already present")
		return nil
	}
	return core.Sh("apt-get install -y podman uidmap")
}

func installRestic() error {
	if core.Have("restic") {
		fmt.Println("restic already present")
		return nil
	}
	return core.Sh("apt-get install -y restic")
}

func installCaddy() error {
	if core.Have("caddy") {
		fmt.Println("caddy already present")
		return nil
	}
	// Official Caddy apt repo: ships caddy.service + a caddy user + the admin API.
	return core.Sh(`
set -euo pipefail
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy
`)
}

// caddyAdminSocket is where Caddy's admin API listens. Not the default localhost:2019,
// which any local user — or any container that can reach the host's loopback — may use
// to replace the whole config. A socket is governed by ownership instead: its directory
// is caddy:steward 2750, so only the caddy user and the steward group can reach it at all.
// See decisions/caddy-admin-socket.md.
const caddyAdminSocket = "/run/caddy-admin/admin.sock"

// configureCaddy points the system Caddy at a steward-owned routing fragment. Caddy runs
// as its own `caddy` user on :80/:443 (the package grants it the right to bind them);
// the steward user writes only its app routes (under /etc/caddy/steward/, where the caddy
// user can still read them) and reloads via the admin socket — so no root is needed in
// the deploy loop. Routing config carries no secrets, so the fragment is world-readable.
// See decisions/open/quadlet-units.md.
//
// The socket's directory lives in /run, which is empty after every boot, so a tmpfiles.d
// entry recreates it before Caddy starts. The directory is setgid: a socket created in it
// takes the steward group, and `|0220` lets that group write to it — connecting to a
// socket needs write permission, so that is the whole grant.
func configureCaddy() error {
	return core.Sh(fmt.Sprintf(`
set -euo pipefail
frag=/etc/caddy/steward
mkdir -p "$frag"
chown %[1]s:%[1]s "$frag"
chmod 0755 "$frag"
if [ ! -e "$frag/apps.caddy" ]; then
  echo '# Managed by steward. No apps deployed.' > "$frag/apps.caddy"
  chown %[1]s:%[1]s "$frag/apps.caddy"
  chmod 0644 "$frag/apps.caddy"
fi
cat > /etc/tmpfiles.d/caddy-admin.conf <<'TMPFILES'
# Managed by steward — the directory holding Caddy's admin socket.
d %[3]s 2750 caddy %[1]s -
TMPFILES
systemd-tmpfiles --create /etc/tmpfiles.d/caddy-admin.conf
cat > /etc/caddy/Caddyfile <<'CADDY'
# Managed by steward — base config. App routes live in /etc/caddy/steward/*.caddy
{
	admin unix/%[2]s|0220
}
import /etc/caddy/steward/*.caddy
CADDY
# A reload reads the admin address from the new config, so while Caddy still listens on
# localhost:2019 it would dial a socket that does not exist yet. The first time, restart.
if [ -S %[2]s ]; then
  systemctl reload caddy
else
  systemctl restart caddy
fi
`, core.StewardUser, caddyAdminSocket, filepath.Dir(caddyAdminSocket)))
}
