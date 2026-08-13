// Build guard: the install page links to the current release, so the signed
// artifacts for the platform VERSION must be present before we build the site.
// Catches "bumped VERSION but didn't run `make release`" and a stale /releases/.
// Runs as the npm `prebuild` step (build only — `serve` stays lenient).
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const version = readFileSync(join(root, "VERSION"), "utf8").trim();

const dir = join(root, "release", "published", "steward", version);

// Every architecture install.sh will ask for. It picks by `uname -m`, so a release
// that published only one of these leaves the other refusing to install — and the
// site would go on advertising a version those machines cannot get. Keep in step
// with ARCHES in steward/Makefile and the case statement in install.sh.
const arches = ["amd64", "arm64"];

function die(msg) {
  console.error(`\n✗ ${msg}\n`);
  process.exit(1);
}

// 1. The signed release for this version must be published, for every architecture.
const missing = arches.flatMap((arch) => {
  const tgz = join(dir, `steward-linux-${arch}.tar.gz`);
  return [tgz, tgz + ".sig"].filter((f) => !existsSync(f));
});
if (missing.length) {
  const have = existsSync(join(root, "release", "published", "steward"))
    ? readdirSync(join(root, "release", "published", "steward")).join(", ") || "none"
    : "none";
  die(
    `Release for v${version} is incomplete.\n` +
      missing.map((f) => `  Missing: ${f.slice(root.length + 1)}`).join("\n") +
      `\n  Published versions: ${have}\n` +
      `  Run \`make -C steward release\` first.`
  );
}

// 2. The install page's copy-paste command must take its version from VERSION
//    rather than from someone's memory. `{{version}}` is filled at build time by
//    site/versions.js, so a page written that way cannot drift; a page with the
//    number typed into it can, and this is what catches the retyping.
//
//    One command, not two: the home page used to also carry a `V=<version>`
//    verify-by-hand block, and that block was cut when the page became the hook.
//    The guard tracks what is on the page — a check for a string that can no longer
//    appear fails every build and teaches people to delete the guard.
const installMd = readFileSync(join(root, "site", "content", "index.md"), "utf8");
const want = "bash -s -- {{version}}";
if (!installMd.includes(want)) {
  die(
    `index.md's install command doesn't read the version from VERSION ` +
      `(looking for "${want}").\n` +
      `  Write {{version}} in site/content/index.md — don't type v${version} in.`
  );
}

console.log(`✓ release + install page consistent at v${version}`);
