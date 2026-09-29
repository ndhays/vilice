module steward

go 1.22

// The toolchain a release is built and audited with. Steward requires no modules, so a
// govulncheck finding is a finding against the toolchain — the fix is a bump here, not a
// code change (see ../decisions/security-audit.md). 1.26.6 carries the net/url,
// crypto/tls, encoding/asn1 and net/http fixes that 1.26.5 lacked. The `go` line above
// stays the language floor, which is a separate thing.
toolchain go1.26.6
