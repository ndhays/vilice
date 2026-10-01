# Vilice Console — Overview

> The canonical, plain-English picture of what this is. Start here.
> Kept deliberately small; it grows only as decisions settle into truth.

**Status:** Canonical. Last touched 2026-06-09.

---

## What this is

A coordination platform for operators running managed services on infrastructure
they control. It is built on the **Agora Constitution** (`blueprint/agora.md`):
every actor is named, every action is accountable, and the privileged ceiling is
small and legible. The articles count only insofar as they are **in the code**, as
mechanism — not as documentation.

---

## The two programs

- **Vilice** — a Go CLI on every machine. It hardens the box, apps the
  dependencies, and deploys applications from the machine itself. It owns the
  privilege and is where Agora becomes mechanism. Detailed spec: `blueprint/vilice/`.

- **Vilice Console** — a Rails app, the human interface. One codebase, whether it reaches
  one box or a hundred: a fleet is the list of machines it holds keys for, not a mode it
  switches into. It reads the record and writes through Vilice. Detailed spec:
  `blueprint/console/`.

The console holds no privilege of its own. It carries a scoped key and comes through the
same door as anyone else — a person at a shell, a CI job, an AI agent. Nothing
orchestrates from beside the door.

Both surfaces — the console and the documentation site — answer to one design system:
`blueprint/design/`. It holds the mark, the tokens, and the shared patterns, so a change
to how either looks has somewhere to be true.

---

## The console runs anywhere

It reaches Vilice over scoped SSH, and SSH is the same call whether it crosses a
loopback or the open internet. So **where the console runs does not matter**:

- in a container on the very box you're inspecting,
- on your laptop,
- on one central server managing a hundred machines.

Same code, same key, same command. There are **no modes** — one console, one design; the
only difference is how many machines it reaches and how far (N and distance), never a
different program. (An earlier framing split this into "Operator" and "Dispatcher"; that
distinction is dropped — see `decisions/ui-shape.md`.)

It also keeps the machines thin: a box runs **only Vilice** (a small static binary),
never a per-box web app. The rich surface reaches in from wherever it happens to live.

---

## The three invariants

These hold regardless of how transport or topology evolve:

1. **Every caller is a named actor with declared scope.**
2. **Every action writes an accountable record before it runs** — append-only,
   hash-chained.
3. **The privileged layer keeps a small, legible ceiling** — enforced by ownership,
   not convention.

If you can't name the mechanism, the article isn't applied.

---

## Where the docs live

- `blueprint/` — **current canonical truth.** What the system *is*, now. Code is a
  projection of this. No history here; when behavior changes, the blueprint changes
  with it.
- `decisions/` — the settled **why**, especially roads not taken.
- `decisions/open/` — questions still being decided (e.g.
  `decisions/open/vilice-open-questions.md`). Truth migrates *out* of here into
  `decisions/` and `blueprint/` as it settles.
