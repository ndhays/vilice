package app

// The substrate this pack runs on, and installing it.
//
// This is the prepare half of the pack boundary. It lives here rather than in the
// ceiling because Podman, Caddy and restic are *this pack's* dependencies, not the
// box's: a box with no app pack needs none of them. The core lays the accountability
// floor and then asks each pack to make itself workable.
//
// The names are the substrate's, not the pack's — the pack promises apps that deploy,
// route and restore; these three are today's way of keeping that promise.

import (
	"fmt"

	"steward/internal/core"
)

// Substrate is what the operator is consenting to when `prepare` asks.
func (Pack) Substrate() core.Substrate {
	return core.Substrate{
		Packages: []string{"podman", "uidmap", "restic"},
		Note:     "plus Caddy from its official apt repo",
	}
}

// Prepare installs the substrate and configures Caddy's routing. Idempotent: each
// step checks before acting, so a second `prepare` converges rather than doubling up.
func (Pack) Prepare() error {
	steps := []struct {
		name string
		fn   func() error
	}{
		{"install podman", installPodman},
		{"install caddy", installCaddy},
		{"install restic", installRestic},
		{"configure caddy routing", configureCaddy},
	}
	for _, s := range steps {
		fmt.Printf("\n=== %s ===\n", s.name)
		if err := s.fn(); err != nil {
			return fmt.Errorf("%s: %w", s.name, err)
		}
	}
	// The pack reports its own substrate, because the pack is what depends on it.
	fmt.Printf("\n  Podman:    %s\n", core.CmdFirstLine("podman", "--version"))
	fmt.Printf("  Caddy:     %s\n", core.CmdFirstLine("caddy", "version"))
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

// configureCaddy points the system Caddy at a steward-owned routing fragment. Caddy
// stays a root service on :80/:443; the steward user writes only its app routes (under
// /etc/caddy/steward/, where the caddy user can still read them) and reloads via the
// local admin API — so no root is needed in the deploy loop. Routing config carries no
// secrets, so the fragment is world-readable. See decisions/open/quadlet-units.md.
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
cat > /etc/caddy/Caddyfile <<'CADDY'
# Managed by steward — base config. App routes live in /etc/caddy/steward/*.caddy
import /etc/caddy/steward/*.caddy
CADDY
systemctl reload caddy
`, core.StewardUser))
}
