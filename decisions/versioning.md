# Versioning and releases

> Decided 2026-06-09. The flow is in `install.sh` and `vilice/Makefile`
> (`sign`/`release`).

## The rule: a version is one set of bytes, forever

`install.sh <version>` verifies an ed25519 signature and installs the binary as root.
That trust holds only if a version number maps to exactly one signed artifact. **Never
republish different bytes under an existing version** — not for a fix, not for a rebuild.

## When to release

A release is a ceremony, at a milestone where the blueprint is true and tests pass:

1. bump `VERSION`;
2. write the version's entry in `audit/log.md` (`release` refuses without it);
3. `make release` — builds every arch in `ARCHES`, signs each tarball separately,
   self-verifies, copies to `release/published/`;
4. commit; 5. tag.

**One signature per artifact.** A signature names exactly the bytes it vouches for.
`install.sh` picks the arch from `uname -m` and refuses one it has no build for.

- **Before 1.0:** betas are checkpoints, not contracts.
- **1.0** when the on-box contract is stable: the command set, the scope model, the
  record format.
- **Patch** = fixes and security; **minor** = new capability.

## Two stores

- **The install host** (`releases/`) is an immutable archive. Keep every stable version;
  an old URL must keep resolving to the same bytes.
- **The local `release/published/` tree** is a working set, not in git. Prune superseded
  betas freely.

The signed artifacts exist only where someone ran `make release`, and deploying the site
is what publishes a version. The `check-release.js` prebuild guard refuses to build a
site whose install line names a `VERSION` the tree lacks. After 1.0 the host should be a
real archive (CI or object storage).

## Security updates: fix forward, yank with a record

- **Never overwrite.** Ship a new patched version.
- **A bad beta:** delete it.
- **A vulnerable stable:** pull it from the install path, and leave a marker — a `YANKED`
  note beside the version and a `SECURITY.md` advisory. An artifact that vanishes with no
  record is its own integrity smell.

## Roads not taken

- **A `latest` endpoint.** A root install names exactly what it trusts.
- **Keeping every beta in git.** Repo weight for no gain.
