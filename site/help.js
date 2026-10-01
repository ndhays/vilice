// The command reference, read from the binary itself at build time.
//
// `vilice _commands` emits the whole command table as JSON, and every entry
// carries the exact page `vilice <name> --help` prints — rendered by the CLI's own
// commandHelp, not by anything here. The site prints that text verbatim. So there
// is no second description of the CLI to keep in step with the first, and no way
// for a published page to disagree with the terminal.
//
// See decisions/help-is-the-documentation.md and blueprint/design/patterns.md.
import { Origami } from "@weborigami/origami";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const binary = join(root, "vilice", "bin", "vilice");

if (!existsSync(binary)) {
  // Fail loud rather than publish a site with no command reference in it.
  throw new Error(
    `vilice binary not found at ${binary}\n` +
      `  The docs are generated from the CLI. Build it first:\n` +
      `    make -C ../vilice build`
  );
}

const table = JSON.parse(execFileSync(binary, ["_commands"], { encoding: "utf8" }));

// Prose a command page adds under the help block. Optional, and usually absent:
// anything the reader needs should be in the help page, where the person at the
// terminal gets it too. A file here is for what genuinely cannot live there.
async function notes(name) {
  const path = join(here, "content", "commands", `${name}.md`);
  if (!existsSync(path)) {
    return "";
  }
  return String(await Origami.mdHtml(readFileSync(path, "utf8")));
}

// Keyed by command name, in the order `vilice help` shows them — the binary's
// own grouping, so the sidebar and the index cannot invent a taxonomy the CLI
// does not have.
const commands = {};
for (const command of table) {
  commands[command.name] = { ...command, notes: await notes(command.name) };
}

export default commands;
