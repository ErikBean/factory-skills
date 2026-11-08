// Prints, as Markdown, how the prod stage synthesized from this checkout
// differs from the templates the last production deploy saved. It needs no
// AWS credentials, so pull request CI can run it. It shows added, removed and
// changed resources, but not drift, and not reliably whether a change
// replaces a resource.
// Usage: node scripts/diff-prod.mjs <last deployed templates dir> <cdk.out dir>
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Writable } from "node:stream";
import { formatDifferences, fullDiff } from "@aws-cdk/cloudformation-diff";

const [before, after] = process.argv.slice(2);
if (!after) {
  console.error("usage: node scripts/diff-prod.mjs <before dir> <after dir>");
  process.exit(2);
}

const templatesIn = (dir) =>
  existsSync(dir) ? readdirSync(dir).filter((name) => name.endsWith(".template.json")) : [];
const read = (dir, name) => JSON.parse(readFileSync(join(dir, name), "utf8"));

console.log("## Production changes\n");
const old = templatesIn(before);
if (old.length === 0) {
  console.log("No saved production templates to compare with. The first deploy, or one more than 90 days ago, saves them.");
  process.exit(0);
}

const names = [...new Set([...old, ...templatesIn(after)])].sort();
let changed = 0;
for (const name of names) {
  const diff = fullDiff(old.includes(name) ? read(before, name) : {}, templatesIn(after).includes(name) ? read(after, name) : {});
  if (diff.isEmpty) continue;
  changed++;
  let text = "";
  const stream = new Writable({ write(chunk, _encoding, done) { text += chunk; done(); } });
  formatDifferences(stream, diff);
  // The formatter colors its output; the job summary shows plain text.
  console.log(`### ${name.replace(/\.template\.json$/, "")}\n\n\`\`\`\n${text.replace(/\x1b\[[0-9;]*m/g, "").trim()}\n\`\`\`\n`);
}
if (changed === 0) console.log("No changes to production stacks.");
