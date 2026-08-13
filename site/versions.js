// The platform version — one number for the whole monorepo, at the repo root.
// Read at build time by site.ori / page.ori.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// Repo root is one level up from site/.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function plainVersion(relPath) {
  return readFileSync(join(root, relPath), "utf8").trim();
}

const platform = plainVersion("VERSION");

export default {
  platform,

  // Fill `{{version}}` in a hand-written page's body. The install line and the
  // version badge quote the current release, and nobody has to retype them at
  // release time — a docs page claiming an old version is a failure mode worth
  // removing rather than remembering. Applied by site.ori to content/*.md.
  fill: (doc) => ({
    ...doc,
    _body: doc._body.replaceAll("{{version}}", platform),
  }),
};
