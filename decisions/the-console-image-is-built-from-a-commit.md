# The console image is built from a commit, with its outside parts as build contexts

> Decided 2026-10-22. Code: `Makefile` (`image`, `push`), `console/Dockerfile`. Settles
> "App image registry" in [`open/console-open-questions.md`](open/console-open-questions.md).

## The decision

`make image` builds the console's image, and `make push` sends it to a registry and
prints the digest to deploy.

- **From commits only.** It refuses uncommitted changes in this repo or in Boxcar, and
  labels the image with both commits (`org.opencontainers.image.revision`,
  `boxcar.revision`) and the version. The tag is this repo's short commit.
- **Two parts live outside `console/`, and arrive as named build contexts:** Boxcar, a
  path gem in a sibling checkout (`--build-context boxcar=../boxcar-rails`), and the
  repo root's `VERSION`, which the console reads at boot (`--build-context repo=.`). The
  Dockerfile copies them to `/boxcar-rails` and `/VERSION`, where the app's relative
  paths already point, in the build stage and the final one.
- **For the boxes' architecture,** `linux/amd64` unless `PLATFORM` says otherwise.
- **No `latest`.** Vilice deploys by digest, so a moving tag would name nothing that runs.
- **Any registry.** `IMAGE` names it; the default is the project's. The maintainer's is a
  self-hosted Zot.

## Why

A tag names the commit, so an image can always be traced to the code in it — the same
rule `make release` follows for the binary
([`versioning.md`](versioning.md)). Build contexts are the build tool's own answer to
"a file outside the context": no copying into the tree, no second Dockerfile, and the
repo's relative paths keep working inside the image.

## Roads not taken

- **Boxcar from a git source.** The standard fix, and the right one once Boxcar is
  public. Until then a build would need credentials for a private repo; that question
  stays open under "The console does not build from a clone".
- **Vendor Boxcar into this repo.** Two copies drifting, and it publishes Boxcar.
- **Stamp `VERSION` with a build argument.** Works, but a second way to pass the version
  when the file can simply be copied.
- **Build from the repo root as the context.** It would send the whole repository —
  the site's `node_modules` among it — to every build.
