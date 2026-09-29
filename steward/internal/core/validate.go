package core

// Input validation the gate applies before any command runs. It lives with the core,
// not with the verbs, because dispatch validates an app name before it knows which
// verb will receive it, and auth refuses control characters before a key is written.

// Everything downstream — the state file, the Quadlet unit, the container and systemd
// unit names — is built by concatenation from this name, so this rule is what keeps
// those inside their directories. dispatch checks it at the door; the three functions
// below check it again where the name actually becomes a path, so a future caller that
// skips the door still can't escape.
func ValidAppName(s string) bool {
	if s == "" {
		return false
	}
	// The first character is narrower than the rest, and for a different reason. A name
	// becomes an *argument*: `systemctl --user stop <app>-a.service`, `podman rm <name>`.
	// A leading dash makes it look like a flag instead, which is argv injection without a
	// shell anywhere in it — an app called `-H` would have systemctl read a host. Dashes
	// and underscores inside a name carry no such risk.
	if first := rune(s[0]); !(first >= 'a' && first <= 'z' || first >= 'A' && first <= 'Z' || first >= '0' && first <= '9') {
		return false
	}
	for _, r := range s {
		ok := r == '-' || r == '_' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !ok {
			return false
		}
	}
	return true
}

// HasControlChar reports whether s holds any C0 control character or DEL. Every file
// Steward writes — authorized_keys, a Caddy site block, a Quadlet unit — is
// line-oriented, so a newline in a value ends its line and the rest becomes a
// directive nobody wrote. There is no legitimate config value here that needs one.
func HasControlChar(s string) bool {
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return true
		}
	}
	return false
}
