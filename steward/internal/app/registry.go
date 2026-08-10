package app

// Private registry credentials (operate scope). A credential is standing box state —
// shared by every app that pulls from a registry, outliving any one app — so it is
// born and dies through its own recorded commands (registry-login / registry-logout),
// never as a side effect of a deploy. Pull failures are classified so an expired
// credential surfaces as an actionable error, not a generic one. See
// decisions/registry-credentials.md and blueprint/steward/deploy.md.

import (
	"steward/internal/core"

	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// authFilePath is the persistent rootless auth file. It is wired into every podman
// call via REGISTRY_AUTH_FILE (see userExec) so login, pull, and logout share one
// file that survives reboot — unlike podman's default under $XDG_RUNTIME_DIR (tmpfs).
// STEWARD_AUTH_FILE overrides it (tests).
func authFilePath() string {
	if p := os.Getenv("STEWARD_AUTH_FILE"); p != "" {
		return p
	}
	return filepath.Join(userHome(), ".config", "containers", "auth.json")
}

// --- registry-login / registry-logout (operate scope) ---

func registryLoginCmd(args []string) core.Result {
	flags, pos := core.ParseArgs(args)
	reg := firstPos(pos)
	username := flags["username"]
	switch {
	case reg == "":
		return core.Result{Code: "bad_args", Message: "missing <registry>"}
	case !validRegistry(reg):
		return core.Result{Code: "bad_args", Message: "registry must be a host, optionally host:port (no path, no spaces)"}
	case username == "":
		return core.Result{Code: "bad_args", Message: "missing --username"}
	}
	password, err := readStdinSecret(os.Stdin)
	if err != nil {
		return core.Result{Code: "bad_args", Message: err.Error()}
	}
	out, err := podmanLogin(reg, username, password)
	if err != nil {
		return core.Result{Code: "login_failed", Retryable: true, Message: firstLine(out, err)}
	}
	return core.OK(fmt.Sprintf("logged in to %s as %s", reg, username))
}

func registryLogoutCmd(args []string) core.Result {
	_, pos := core.ParseArgs(args)
	reg := firstPos(pos)
	if reg == "" {
		return core.Result{Code: "bad_args", Message: "missing <registry>"}
	}
	if !validRegistry(reg) {
		return core.Result{Code: "bad_args", Message: "registry must be a host, optionally host:port (no path, no spaces)"}
	}
	out, err := podmanLogout(reg)
	if err != nil {
		if strings.Contains(strings.ToLower(out), "not logged in") {
			return core.Result{Code: "not_found", Message: fmt.Sprintf("not logged in to %s", reg)}
		}
		return core.Result{Code: "logout_failed", Message: firstLine(out, err)}
	}
	return core.OK(fmt.Sprintf("logged out of %s", reg))
}

// podmanLogin writes the credential via stdin (never argv) into the persistent auth
// file. rm-then-create is podman's own job here; login is idempotent.
func podmanLogin(reg, username, password string) (string, error) {
	if err := os.MkdirAll(filepath.Dir(authFilePath()), 0o700); err != nil {
		return "", err
	}
	c := userExec("podman", "login", reg, "--username", username, "--password-stdin")
	c.Stdin = strings.NewReader(password)
	out, err := c.CombinedOutput()
	return string(out), err
}

func podmanLogout(reg string) (string, error) {
	out, err := userExec("podman", "logout", reg).CombinedOutput()
	return string(out), err
}

// readStdinSecret reads a single secret value (a registry password) from stdin and
// trims the trailing newline. It refuses a terminal rather than block waiting for input.
func readStdinSecret(f *os.File) (string, error) {
	if info, err := f.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		return "", fmt.Errorf("no password on stdin (pipe it: printf %%s <token> | steward registry-login …)")
	}
	b, err := io.ReadAll(f)
	if err != nil {
		return "", err
	}
	s := strings.TrimRight(string(b), "\r\n")
	if s == "" {
		return "", fmt.Errorf("empty password on stdin")
	}
	return s, nil
}

// validRegistry accepts a registry host, optionally with a port: letters, digits, and
// .:-_ — no path segment, no whitespace. (podman login takes a host, not an image ref.)
func validRegistry(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		case r == '.', r == ':', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

// --- pull (with the local-image short-circuit + error classification) ---

// imageExists reports whether the digest-pinned image is already in local storage.
// Digest-pinned images are immutable, so a present one is the right bits.
func imageExists(image string) bool {
	return userExec("podman", "image", "exists", image).Run() == nil
}

// pullImage pulls an image, classifying a failure into a coded error so the caller can
// surface an actionable result (e.g. an expired credential → registry_auth). The pull
// output is captured to classify it.
func pullImage(image string) error {
	out, err := podmanOutput("pull", image)
	if err == nil {
		return nil
	}
	code, retryable, hint := classifyPullError(registryOf(image), out)
	return &codedError{code: code, retryable: retryable, msg: hint}
}

// codedError carries a result code up from deep in the deploy pipeline so deployCmd can
// settle a specific, actionable outcome instead of a generic deploy_failed.
type codedError struct {
	code      string
	retryable bool
	msg       string
}

func (e *codedError) Error() string { return e.msg }

// resultFromErr turns an error into a result, preserving a codedError's code/retryable
// and otherwise falling back to def (retryable).
func resultFromErr(err error, def string) core.Result {
	var ce *codedError
	if errors.As(err, &ce) {
		return core.Result{Code: ce.code, Retryable: ce.retryable, Message: ce.msg}
	}
	return core.Result{Code: def, Retryable: true, Message: err.Error()}
}

// classifyPullError maps podman pull output to a result code + a plain-language hint.
// auth → the box's credential is wrong/expired (retryable after a re-login); unreachable
// → network (retryable); not-found → a bad digest (not retryable).
func classifyPullError(registry, out string) (code string, retryable bool, hint string) {
	low := strings.ToLower(out)
	switch {
	case containsAny(low, "unauthorized", "authentication required", "access to the resource is denied", "denied: requested access", "error: 401", "error: 403", " 401 ", " 403 "):
		return "registry_auth", true, fmt.Sprintf(
			"can't pull from %s: authentication failed — the box's credential may be missing or expired. Run `steward registry-login %s` and redeploy.", registry, registry)
	case containsAny(low, "no such host", "connection refused", "i/o timeout", "timeout exceeded", "tls handshake", "dial tcp", "temporary failure in name resolution", "network is unreachable", "connection timed out"):
		return "registry_unreachable", true, fmt.Sprintf("can't reach registry %s: %s", registry, lastLine(out))
	case containsAny(low, "manifest unknown", "not found", "error: 404", " 404 "):
		return "image_not_found", false, fmt.Sprintf("image not found in %s: %s", registry, lastLine(out))
	default:
		return "pull_failed", true, fmt.Sprintf("pull from %s failed: %s", registry, lastLine(out))
	}
}

// registryOf extracts the registry host from an image reference. Docker's rule: the
// first path segment is a registry only if it has a '.' or ':' or is "localhost";
// otherwise the image lives on Docker Hub.
func registryOf(image string) string {
	ref := image
	if i := strings.Index(ref, "@"); i >= 0 {
		ref = ref[:i]
	}
	slash := strings.Index(ref, "/")
	if slash < 0 {
		return "docker.io"
	}
	first := ref[:slash]
	if strings.ContainsAny(first, ".:") || first == "localhost" {
		return first
	}
	return "docker.io"
}

// --- the inspectable ledger: which registries the box is logged into ---

// registryLogin is one entry the box holds — host and username only; the secret is
// never read out of the auth file.
type registryLogin struct {
	Host     string `json:"host"`
	Username string `json:"username,omitempty"`
}

// loggedInRegistries reads the persistent auth file and returns the registries the box
// can pull from, secrets redacted. A missing file means none.
func loggedInRegistries() []registryLogin {
	b, err := os.ReadFile(authFilePath())
	if err != nil {
		return nil
	}
	return parseAuthFile(b)
}

// parseAuthFile reads a containers auth.json ({"auths":{"host":{"auth":"<b64 user:pass>"}}})
// into host+username entries, sorted by host. The base64 auth holds the password too, so
// we decode only the username (before the first ':') and drop the rest.
func parseAuthFile(data []byte) []registryLogin {
	var f struct {
		Auths map[string]struct {
			Auth string `json:"auth"`
		} `json:"auths"`
	}
	if json.Unmarshal(data, &f) != nil {
		return nil
	}
	var out []registryLogin
	for host, entry := range f.Auths {
		out = append(out, registryLogin{Host: host, Username: usernameFromAuth(entry.Auth)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Host < out[j].Host })
	return out
}

// usernameFromAuth decodes the username from a base64 "user:pass" token, discarding the
// password. An undecodable token yields "" (host still listed).
func usernameFromAuth(b64 string) string {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return ""
	}
	if i := strings.IndexByte(string(raw), ':'); i >= 0 {
		return string(raw[:i])
	}
	return ""
}

// renderRegistries is the registries block in `status` text output.
func renderRegistries(regs []registryLogin) string {
	var b strings.Builder
	b.WriteString("registries\n")
	for _, r := range regs {
		if r.Username != "" {
			fmt.Fprintf(&b, "  %-24s user: %s\n", r.Host, r.Username)
		} else {
			fmt.Fprintf(&b, "  %s\n", r.Host)
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

// registryCoverageCheck reports which registries the deployed apps reference and which
// the box has a login for. It stays OK=true on principle: a registry with no login may
// simply be public, and doctor can't know that without a network probe — so it informs,
// it doesn't fail (true-or-absent: report only what it can know).
func registryCoverageCheck(apps []appState, logins []registryLogin) check {
	const name = "registry logins"
	loggedIn := map[string]bool{}
	for _, l := range logins {
		loggedIn[l.Host] = true
	}
	seen := map[string]bool{}
	var have, missing []string
	for _, a := range apps {
		r := registryOf(a.Image)
		if r == "" || seen[r] {
			continue
		}
		seen[r] = true
		if loggedIn[r] {
			have = append(have, r)
		} else {
			missing = append(missing, r)
		}
	}
	if len(seen) == 0 {
		return check{Name: name, OK: true, Note: "no app registries in use"}
	}
	sort.Strings(have)
	sort.Strings(missing)
	var parts []string
	if len(have) > 0 {
		parts = append(parts, "logged in: "+strings.Join(have, ", "))
	}
	if len(missing) > 0 {
		parts = append(parts, "no login (ok if public): "+strings.Join(missing, ", "))
	}
	return check{Name: name, OK: true, Note: strings.Join(parts, "; ")}
}

// --- small helpers ---

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}

func firstLine(out string, err error) string {
	if s := strings.TrimSpace(out); s != "" {
		return strings.SplitN(s, "\n", 2)[0]
	}
	return err.Error()
}

func lastLine(out string) string {
	lines := core.NonEmptyLines(out)
	if len(lines) == 0 {
		return "no output"
	}
	return strings.TrimSpace(lines[len(lines)-1])
}
