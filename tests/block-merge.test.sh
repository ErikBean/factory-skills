#!/usr/bin/env bash
# Tests for skills/factory-repo-setup/templates/claude/hooks/block-merge.mjs,
# the PreToolUse hook that refuses merges, approvals and pushes to main.
# Each case pipes a Claude Code tool call to the hook and checks its exit code:
# 2 blocks the call, 0 allows it.
set -euo pipefail

hook="$(cd "$(dirname "$0")/.." && pwd)/skills/factory-repo-setup/templates/claude/hooks/block-merge.mjs"
failures=0

# Runs the hook on a Bash tool call whose command is $1, and prints its exit code.
run() {
  local input
  input="$(node -e 'process.stdout.write(JSON.stringify({tool_name: "Bash", tool_input: {command: process.argv[1]}}))' "$1")"
  set +e
  printf '%s' "$input" | node "$hook" 2>/dev/null
  echo $?
  set -e
}

expect() {
  local want="$1" cmd="$2" got
  got="$(run "$cmd")"
  if [[ "$got" != "$want" ]]; then
    echo "  expected exit $want, got $got: $cmd" >&2
    failures=$((failures + 1))
  fi
}

# Blocked: merging, approving and pushing to main, in the usual spellings.
expect 2 'gh pr merge 12 --squash'
expect 2 'gh pr merge --auto --merge'
expect 2 'GH_TOKEN=x gh  pr   merge 3'
expect 2 'gh pr review 12 --approve'
expect 2 'gh pr review 12 -a -b "looks good"'
expect 2 'gh api -X PUT repos/o/r/pulls/12/merge'
expect 2 "gh api repos/o/r/pulls/12/reviews -f event=APPROVE"
expect 2 "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'"
expect 2 "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'"
expect 2 'curl -X POST https://api.github.com/repos/o/r/merges'
expect 2 'git push origin main'
expect 2 'git push -u origin HEAD:main'
expect 2 'git push --force origin +main'
expect 2 'git push origin HEAD:refs/heads/main'
expect 2 'npm test && git push origin master'
expect 2 "git -c 'credential.helper=!gh auth git-credential' push https://github.com/o/r.git HEAD:main"

# Allowed: ordinary work, including the setup skill's own commands.
expect 0 'git push -u origin factory/add-login'
expect 0 'git push origin HEAD:factory-setup'
expect 0 "git -c 'credential.helper=!gh auth git-credential' push https://github.com/o/r.git HEAD:refs/heads/factory-setup"
expect 0 'git merge --allow-unrelated-histories -X ours -m "Merge initial commit" origin/main'
expect 0 'git fetch origin main'
expect 0 'gh pr create --base main --head factory/x --title t --body b'
expect 0 'gh pr review 12 --comment -b "see inline"'
expect 0 'gh pr view 12 --json mergeable'
expect 0 'npm test'

# Malformed input is allowed, so a broken hook never stops work.
set +e
printf 'not json' | node "$hook" 2>/dev/null
code=$?
set -e
if [[ "$code" != 0 ]]; then
  echo "  expected exit 0 on malformed input, got $code" >&2
  failures=$((failures + 1))
fi

# The blocking message reaches the agent on stderr.
msg="$(printf '{"tool_input":{"command":"gh pr merge 1"}}' | node "$hook" 2>&1 >/dev/null || true)"
if [[ "$msg" != *"only the human merges"* ]]; then
  echo "  missing explanation on stderr: $msg" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  echo "  $failures case(s) failed" >&2
  exit 1
fi
echo "  all cases passed"
