#!/usr/bin/env node
// Claude Code PreToolUse hook on Bash: refuses shell commands that would merge
// a pull request, approve one, or push to the default branch. The decision to
// merge belongs to the human.
//
// This is a second layer, not the boundary. The repo's rulesets are: an
// approval from a code owner is required, and the agents' GitHub App can't give
// one. This hook makes an attempt fail fast and explains why, instead of
// leaving the agent to discover the ruleset by trial.
//
// Reads the tool call as JSON on stdin. Exit 2 blocks the call and shows stderr
// to the agent. Any error in the hook itself allows the call, so a broken hook
// never stops work; the ruleset still holds.
// Idea from addyosmani/factory's block-merge.sh (MIT), narrowed so ordinary
// local `git merge` still works.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const PROTECTED = ["main", "master"];

/** Returns the reason to block `command`, or null to allow it. */
export function reasonToBlock(command) {
  const cmd = command.replace(/\s+/g, " ");
  if (/\bgh pr merge\b/.test(cmd)) return "gh pr merge";
  if (/\bgh pr review\b/.test(cmd) && /(\s--approve\b|\s-a\b)/.test(cmd)) return "approving a pull request";
  if (/\/pulls\/\d+\/merge\b/.test(cmd)) return "the GitHub merge API";
  if (/\/pulls\/\d+\/reviews\b/.test(cmd) && /APPROVE/.test(cmd)) return "approving through the GitHub API";
  if (/\b(mergePullRequest|enablePullRequestAutoMerge)\b/.test(cmd)) return "the GitHub merge API";
  if (/\brepos\/[^/\s]+\/[^/\s]+\/merges\b/.test(cmd)) return "the GitHub merge API";
  for (const push of cmd.matchAll(/\bgit\b[^;&|]*?\spush\b([^;&|]*)/g)) {
    const args = push[1].trim().split(" ").filter(Boolean);
    const targets = args.filter((a) => !a.startsWith("-")).slice(1);
    for (const t of targets) {
      const dst = t.includes(":") ? t.slice(t.lastIndexOf(":") + 1) : t;
      const name = dst.replace(/^\+/, "").replace(/^refs\/heads\//, "");
      if (PROTECTED.includes(name)) return `a push to ${name}`;
    }
  }
  return null;
}

function main() {
  let command = "";
  try {
    command = JSON.parse(readFileSync(0, "utf8"))?.tool_input?.command ?? "";
  } catch {
    process.exit(0);
  }
  const reason = reasonToBlock(String(command));
  if (!reason) process.exit(0);
  process.stderr.write(
    `Blocked by the factory's merge guard: ${reason}.\n` +
      "Merging to main deploys to production, so only the human merges, after approving the pull request.\n" +
      "Open or update the pull request and stop. Don't look for another way to merge.\n",
  );
  process.exit(2);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
