#!/usr/bin/env bash
# Box-posture audit: measure a prepared+hardened box with the field's standard tools,
# so the hardening claim isn't hand-waved. Run against a real box (the devbox), read the
# findings, and fold regressions back into harden/. The counterpart to `make audit`
# (which audits the Go code) — this audits the running machine.
#
#   ssh-audit  — sshd key-exchange / cipher / MAC posture (validates harden/10-ssh.sh)
#   nmap       — what's actually reachable from outside (validates the firewall; catches
#                a provider firewall that ufw can't see — see what-could-go-wrong.md)
#   lynis      — general OS hardening audit, run on the box over SSH
#
# Raw output lands in audit/out/ (gitignored). Record the verdict by hand in
# audit/log.md — that committed ledger is the "v0.1.x was audited" attestation.
#
# Usage:  make audit-box HOST=devbox        (or: vilice/audit/run.sh devbox)
# HOST is an ssh-reachable target (a config alias or user@host).
set -euo pipefail

HOST="${1:-${HOST:-}}"
if [ -z "$HOST" ]; then
  echo "usage: $0 <ssh-host>   (e.g. $0 devbox)" >&2
  exit 2
fi

# Ports we expect open to the world. Anything else is a finding.
EXPECTED_PORTS="${EXPECTED_PORTS:-22,80,443}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/out/$(date -u +%Y%m%dT%H%M%SZ)-$HOST"
mkdir -p "$OUT"
echo "writing raw output to $OUT"

have() { command -v "$1" >/dev/null 2>&1; }
# Each tool that couldn't run. A skipped tool measured nothing, so the run fails at the
# end: an audit that can't fail isn't one, and "done." over three skips read as a pass.
missing=()
ssh_host_only() { printf '%s' "${HOST##*@}"; }  # strip user@ for network tools

run_step() {
  local name="$1"; shift
  echo
  echo "── $name ─────────────────────────────────────────────"
  if "$@" >"$OUT/$name.txt" 2>&1; then
    echo "  ok → $OUT/$name.txt"
  else
    echo "  finished with findings (exit $?) → $OUT/$name.txt"
  fi
  tail -n 20 "$OUT/$name.txt" | sed 's/^/  /'
}

# ── ssh-audit: sshd posture ────────────────────────────────────────────────
if have ssh-audit; then
  run_step ssh-audit ssh-audit "$(ssh_host_only)"
else
  echo "ssh-audit not installed here — skipped (pipx install ssh-audit, or your package manager)"
  missing+=("ssh-audit (here)")
fi

# ── nmap: what's actually reachable ────────────────────────────────────────
if have nmap; then
  # Every port, so an unexpected one can't hide. ufw drops rather than refuses, so each
  # closed port waits out a timeout: without a floor on the rate this takes most of an
  # hour and looks hung. About two minutes this way.
  echo
  echo "nmap: scanning all 65535 ports on $(ssh_host_only), about two minutes…"
  run_step nmap nmap -Pn -p- --open -T4 --max-retries 1 --min-rate 1000 "$(ssh_host_only)"
  # Flag any open port outside the expected set.
  opened=$(awk '/^[0-9]+\/tcp +open/{sub("/.*","",$1); print $1}' "$OUT/nmap.txt" | sort -un | paste -sd',' -)
  echo "  open ports: ${opened:-none}   (expected: $EXPECTED_PORTS)"
  extra=$(comm -23 <(tr ',' '\n' <<<"$opened" | sort -u) <(tr ',' '\n' <<<"$EXPECTED_PORTS" | sort -u) | paste -sd',' -)
  [ -n "$extra" ] && echo "  ⚠ unexpected open ports: $extra"
else
  echo "nmap not installed here — skipped (your package manager: nmap)"
  missing+=("nmap (here)")
fi

# ── lynis: on-box OS hardening audit ───────────────────────────────────────
# Run on the box (it inspects the live system). Needs root there.
echo
echo "── lynis (on $HOST) ──────────────────────────────────"
if ssh "$HOST" 'command -v lynis >/dev/null 2>&1'; then
  ssh "$HOST" 'sudo lynis audit system --quick --no-colors 2>&1' >"$OUT/lynis.txt" 2>&1 || true
  grep -E 'Hardening index|Warning|Suggestion' "$OUT/lynis.txt" | head -n 30 | sed 's/^/  /' || true
  echo "  full report → $OUT/lynis.txt"
else
  echo "  lynis not installed on $HOST — skipped (sudo apt install lynis, there)"
  missing+=("lynis (on $HOST)")
fi

echo
if [ "${#missing[@]}" -gt 0 ]; then
  list="$(printf '%s, ' "${missing[@]}")"
  echo "INCOMPLETE — not measured: ${list%, }."
  echo "Install them and run it again; an entry in audit/log.md needs all three."
  exit 1
fi
echo "done. Read the findings, fold regressions into harden/, and record the verdict in"
echo "audit/log.md (date, ssh-audit grade, open ports, Lynis index, govulncheck/gosec)."
