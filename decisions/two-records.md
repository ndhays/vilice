# Two records — the box's and the control plane's

> Settled. There is not one record but two, by layer; neither subsumes the other.
> And Vilice Console's record is **not** hash-chained (Vilice's is). Anchors the
> ingestion design and the coming Boxcar audit.

**Status:** Settled 2026-06-10.

---

## The two records

- **Vilice's record** — the *box's* truth. What touched this machine's power
  (deploy, start/stop, authorize, reboot). Hash-chained, append-only (`chattr +a`),
  shipped off-host, per-machine. Authoritative for **what happened to the box**.
  Un-bypassable: every privileged act funnels through the scoped SSH gate, which
  records-before-act (Invariant 2).
- **Vilice Console's record** — the *control plane's* truth. What operators did in the
  fleet UI — the human/fleet layer Vilice structurally cannot see. Authoritative
  for **what happened in the cockpit**.

"Vilice is the sole recorder" is true **for the box**. It is *not* true for the
control plane. Agora Invariant 2 applies to Vilice Console at its own layer, so Vilice Console
must keep its own record of its own privileged acts.

## What only Vilice Console can record

These never appear in any single box's Vilice record:

1. **Domain mutations with no box involved** — created Project Acme, linked devbox to
   Acme, stored/rotated an SSH key, added a label, starred a project.
2. **Human attribution** — Vilice records the *client identity* of the key
   (`client=console`); only Vilice Console knows the **human** (alice) behind it. The
   operator→client mapping is the foundation of delegation.
3. **Fleet-level grouping** — "deploy to A *and* B" is one operator-initiated act;
   each box records its half, only Vilice Console holds the act that spanned them.
4. **Intent + outcome at the edge** — record-before-act at the Vilice Console boundary; a
   **refused or failed** command never reaches the box, so it has no Vilice record —
   but the *attempt* is exactly what accountability wants.
5. **Access / observe worth tracking** — exports and sensitive reads don't touch the
   box (so Vilice won't log them), but "who exported db-1's record" is a control-plane
   fact.
6. **Vilice Console's own security/config** — logins, sessions, delegation grants,
   connecting/disconnecting a machine.

## Mirror ≠ record

For everything that *did* touch a box, Vilice Console **mirrors** Vilice's record for a
unified display and search. That mirror is **re-derivable — a cache, never
authoritative**; re-pull and it rebuilds. So `Event` carries two distinct things that
must not be conflated:

- **Vilice Console's own acts** (items 1–6) — *authoritative*, Vilice Console-owned, **not**
  re-derivable.
- **A mirror of Vilice's record** — a re-derivable read cache for display.

The displayed timeline (the "chain") is a **merge** of the two — which is also where
*authored* (Vilice Console ran it, with a human behind it) vs *witnessed* (it appeared in
the box record from elsewhere) comes from, cleanly, **by layer** rather than by string
matching.

## Decision: Vilice Console's record is NOT hash-chained

A hash chain earns its cost only at an **un-bypassable privilege boundary with an
anchor outside the attacker's reach**. Vilice has both (on-box, `chattr +a`, shipped
off-host) — tamper-evident even against a rogue admin on that machine. That is
load-bearing precisely because of the cases that worry us: **two Vilice Consoles driving
one box, or an admin doing manual things**. Every such path still funnels through
Vilice's gate into its chained, off-shipped record.

Vilice Console's record lives in its own DB. A chain **stored in the same DB it protects**
is theater — anyone who can write the rows can recompute it; tamper-evidence needs an
anchor the attacker can't reach, and Vilice Console would be self-anchoring. And it's
unnecessary: **the box record is already that external anchor.** Anything that touched
a box is independently in Vilice's chain, so Vilice Console's account is *cross-checkable
against a chain it doesn't control* — strictly better than a self-anchored one, and
free.

**Rails has no native pattern** for this anyway: `audited`/`paper_trail` are versioning,
not tamper-evidence; `ActiveRecord::Encryption` is confidentiality, not integrity.
Hand-rolling a `before_create` chain would be off-path *and* low-value here.

**Instead, Vilice Console relies on:** append-only **by convention** (no edit/delete paths
for the record), record-before-act with human attribution, normal DB integrity/backups,
and cross-checkability against Vilice for anything box-touching. If a real compliance
case ever demands tamper-evidence for Vilice Console-only acts, the move is **external
anchoring** (ship digests to an append-only store / SIEM) — a road noted, not taken.

**Refinement (Wave 3):** "append-only" means the recorded *facts* never change. A
witnessed act's **outcome** is the one exception — it settles **once**, pending →
ok/failed, on the same entry (record-before-act records it running; the result is
appended when it returns). See
[record-outcome-on-the-entry.md](record-outcome-on-the-entry.md).

## Consequences

- `Event` is **two concerns**: Vilice Console's authoritative own-record + a re-derivable
  Vilice mirror. `data-model.md` corrected to say so.
- Ingestion (the mirror) is a plain cached read — build now, Boxcar-irrelevant
  (option A).
- Vilice Console's **own** record is what Boxcar `Eventable` would model (Agora Article
  II/VIII at the app layer); its persistence shape — and whether `Event` becomes
  `Eventable` — is deferred to the Boxcar audit. No hash chain either way.
