// Prints the URLs a deploy produced, one per line: every stack output whose
// key starts with "Url" in the file `cdk deploy --outputs-file` wrote. The
// preview workflow posts them on the pull request, and smoke.mjs tests them.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function stackUrls(outputsFile) {
  const outputs = JSON.parse(readFileSync(outputsFile, "utf8"));
  return Object.values(outputs).flatMap((stack) =>
    Object.entries(stack)
      .filter(([key, value]) => key.startsWith("Url") && /^https?:\/\//.test(value))
      .map(([, value]) => value),
  );
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) {
    console.error("usage: node scripts/stack-urls.mjs <outputs.json>");
    process.exit(2);
  }
  for (const url of stackUrls(process.argv[2])) console.log(url);
}
