This project is built on the **Agora Constitution** (`blueprint/agora.md`).
Agora is encoded as *mechanism, not commentary* — to apply an article you must
point to the code that enforces it. Three invariants hold everywhere:

1. Every caller is a **named actor with declared scope**.
2. Every action writes an **accountable record before it runs** (append-only,
   hash-chained).
3. The privileged layer keeps a **small, legible ceiling** — enforced by
   ownership, not convention.

If you can't name the mechanism, you haven't applied the article.

# Building safely

Building with an LLM in the loop calls for the same discipline the system enforces.
Three rules, mirroring the invariants:

- **Bound what each step can touch.** One concern at a time; small, scoped changes.
- **Make its effects observable.** Run it, test it, read the diff — never a silent change.
- **Don't commit anything you can't reverse.** Work in small, revertible steps.

# The doc model

Three folders, three jobs. Truth flows in one direction: `decisions/open/` →
`decisions/` + `blueprint/`.

- **`blueprint/` — current canonical truth.** What the system *is*, right now. Code
  is a projection of this. **No history lives here** — when behavior changes, the
  blueprint changes *in the same change*. Drift turns the schema into fiction.
  - **Start at `blueprint/overview.md`** before making changes.
  - **Human-readable filenames.** Overviews are human prose. Fine-grained specs go
    in **subfolders** (e.g. `blueprint/vilice/`) and may be more technical/spec-like.
  - History, if wanted, lives in a single `blueprint/project-history.md` — never
    smeared across the canonical docs.

- **`decisions/` — the settled *why*.** Especially **roads not taken** and reasoning
  git can't surface. Write one when you choose between real alternatives, so settled
  questions aren't re-litigated.

- **`decisions/open/` — questions still being decided.** Planning docs and open
  threads live here (e.g. `decisions/open/vilice-open-questions.md`). As a piece
  settles, its truth **migrates out**: into `decisions/` (the why) and `blueprint/`
  (the canonical schema). Once a doc here is fully graduated, retire it — git keeps
  the history.

When you settle something, move it up the chain and mark what it superseded.

## Before you commit (behavior changes)

When a change alters behavior, in the **same commit**:

1. **Update the blueprint** so it still matches the code. Drift = fiction.
2. **Sweep `decisions/open/`** — did this change *answer* a question? Move it out (into
   the spec, plus a `decisions/` note) — don't leave it stale. Did it *raise* one? Add
   it. **Trim or remove** anything now moot. (Trimming is the common case.)
3. Settled "why" / a road not taken → a `decisions/` entry.

Skip for trivial commits (typos, formatting). The point is to keep `blueprint/` and
`decisions/open/` honest, not to add ceremony.

# Defaults

- **Prefer the boring long-term solution.** A second VM over a clever flag; a standard
  tool in its native idiom over a wrapper; the fix that removes a failure mode over the
  one that handles it. (The Agora preamble's "deeply skeptical of innovation," applied
  to day-to-day choices.)

- When making UI changes, do not bother with inspecting the actual result. Browser tools
  are not connected so the Chrome plugin is disabled. All UI (appearance) should be tested 
  by a human manually.

# Conventions (where preferences live)

**Project-wide preferences live here, in this file.** Surface-specific style lives
in that surface's README — e.g. `site/README.md` holds the docs-site conventions
(Title Case headings, contents lines, true-or-absent copy).

## Naming — the Orwellian test

Prefer plain, clear language. Apply Orwell's rules to **public-facing copy** *and* to
**code** (class names, method names, files, commands):

- Never use a long word where a short one will do.
- If a word can be cut, cut it.
- Prefer a plain word over jargon, abstraction, or a clever coinage.

A name should say what the thing *is* in the fewest plain words. Clarity over
cleverness. If a reader needs the docs to decode a name, the name failed.
