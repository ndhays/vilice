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
const tgz = join(dir, "steward-linux-amd64.tar.gz");

function die(msg) {
  console.error(`\n✗ ${msg}\n`);
  process.exit(1);
}

// 1. The signed release for this version must be published.
if (!existsSync(tgz) || !existsSync(tgz + ".sig")) {
  const have = existsSync(join(root, "release", "published", "steward"))
    ? readdirSync(join(root, "release", "published", "steward")).join(", ") || "none"
    : "none";
  die(
    `Release for v${version} is missing.\n` +
      `  Expected: release/published/steward/${version}/steward-linux-amd64.tar.gz (+ .sig)\n` +
      `  Published versions: ${have}\n` +
      `  Run \`make -C steward release\` first.`
  );
}

// 2. The install page's copy-paste command must reference this exact version, so
//    the page can't drift from VERSION.
//
//    One command, not two: the home page used to also carry a `V=<version>`
//    verify-by-hand block, and that block was cut when the page became the hook.
//    The guard tracks what is on the page — a check for a string that can no longer
//    appear fails every build and teaches people to delete the guard.
const installMd = readFileSync(join(root, "site", "content", "index.md"), "utf8");
const want = `bash -s -- ${version}`;
if (!installMd.includes(want)) {
  die(
    `index.md does not reference v${version} (looking for "${want}").\n` +
      `  Update site/content/index.md to the current version.`
  );
}

console.log(`✓ release + install page consistent at v${version}`);
