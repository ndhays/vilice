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

export default {
  platform: plainVersion("VERSION"),
};
