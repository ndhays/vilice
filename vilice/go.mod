module vilice

go 1.22

// The toolchain a release is built and audited with. Vilice requires no modules, so a
// govulncheck finding is a finding against the toolchain — the fix is a bump here, not a
// code change (see ../decisions/security-audit.md). 1.27.4 carries the net/http fix
// (GO-2026-6859) that 1.27.3 lacked. The `go` line above stays the language floor, which
// is a separate thing.
toolchain go1.27.4
