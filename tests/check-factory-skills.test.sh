#!/usr/bin/env bash
# The test_ functions run through declare -F at the end.
# shellcheck disable=SC2329
# Tests for skills/factory-repo-setup/templates/check-factory-skills.mjs.
# Each test builds a fake factory-skills repo and a project pinned to one of
# its commits, then runs the check in the project against the fake repo.
set -euo pipefail

check="$(cd "$(dirname "$0")/.." && pwd)/skills/factory-repo-setup/templates/check-factory-skills.mjs"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# Runs outside Actions unless a test says otherwise.
unset GITHUB_ACTIONS GITHUB_STEP_SUMMARY

fail() {
  echo "  $*" >&2
  exit 1
}

# Commits a change to skills/$2/SKILL.md (or to $2 itself if it has a slash)
# in the repo at $1, with subject $3.
change() {
  local file="skills/$2/SKILL.md"
  case "$2" in */*) file="$2" ;; esac
  mkdir -p "$1/$(dirname "$file")"
  echo "$3" >> "$1/$file"
  git -C "$1" add -A
  git -C "$1" commit -qm "$3"
}

# Makes a factory-skills repo at $1/src with two stage skills and repo setup,
# and a project at $1/dst pinned to its first commit.
setup() {
  local src="$1/src" dst="$1/dst"
  git init -q -b main "$src"
  for name in factory-orchestrator factory-implementer factory-repo-setup; do
    mkdir -p "$src/skills/$name"
    echo "# $name" > "$src/skills/$name/SKILL.md"
  done
  echo "# factory-skills" > "$src/README.md"
  git -C "$src" add -A
  git -C "$src" commit -qm "skills"
  mkdir -p "$dst/.agents"
  cat > "$dst/.agents/factory-skills.json" <<JSON
{
  "source": "git@github.com:example/factory-skills.git",
  "commit": "$(git -C "$src" rev-parse HEAD)",
  "skills": ["factory-implementer", "factory-orchestrator"]
}
JSON
}

# Runs the check in $1/dst against $1/src, saving its output to $1/out.txt.
run() {
  (cd "$1/dst" && node "$check" "$1/src") > "$1/out.txt" 2>&1 || fail "exited non-zero: $(cat "$1/out.txt")"
}

test_up_to_date() {
  local t="$work/1"; setup "$t"
  run "$t"
  grep -q "up to date" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_behind_names_the_skills_and_commits() {
  local t="$work/2"; setup "$t"
  change "$t/src" factory-implementer "Tighten the green stage"
  change "$t/src" factory-orchestrator "Ask before shipping"
  run "$t"
  grep -q "Factory skills behind" "$t/out.txt" || fail "no warning: $(cat "$t/out.txt")"
  grep -q "2 commits behind" "$t/out.txt" || fail "wrong count: $(cat "$t/out.txt")"
  grep -q "Changed: factory-implementer, factory-orchestrator" "$t/out.txt" || fail "skills not named: $(cat "$t/out.txt")"
  grep -q "Tighten the green stage" "$t/out.txt" || fail "commit not listed"
  grep -q "sync-factory-skills.sh" "$t/out.txt" || fail "no update hint"
}

test_ignores_changes_outside_the_stage_skills() {
  local t="$work/3"; setup "$t"
  change "$t/src" factory-repo-setup "Change repo setup"
  change "$t/src" README.md "Change the README"
  run "$t"
  grep -q "up to date" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_counts_a_stage_skill_added_upstream() {
  local t="$work/4"; setup "$t"
  change "$t/src" factory-docs-writer "Add a docs stage"
  run "$t"
  grep -q "Changed: factory-docs-writer" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_pin_not_on_the_default_branch() {
  local t="$work/5"; setup "$t"
  git -C "$t/src" switch -qc side
  change "$t/src" factory-implementer "Unmerged"
  sed -i "s/\"commit\": \"[0-9a-f]*\"/\"commit\": \"$(git -C "$t/src" rev-parse HEAD)\"/" "$t/dst/.agents/factory-skills.json"
  git -C "$t/src" switch -q main
  run "$t"
  grep -q "isn't on the default branch" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_unreachable_source_only_warns() {
  local t="$work/6"; setup "$t"
  (cd "$t/dst" && node "$check" "$t/missing") > "$t/out.txt" 2>&1 || fail "exited non-zero"
  grep -q "Factory skills not checked" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_no_pin_file() {
  local t="$work/7"; mkdir -p "$t"
  (cd "$t" && node "$check") > "$t/out.txt" 2>&1 || fail "exited non-zero"
  grep -q "No .agents/factory-skills.json" "$t/out.txt" || fail "$(cat "$t/out.txt")"
}

test_annotates_and_summarizes_in_actions() {
  local t="$work/8"; setup "$t"
  change "$t/src" factory-implementer "Tighten the green stage"
  touch "$t/summary.md"
  (cd "$t/dst" && GITHUB_ACTIONS=true GITHUB_STEP_SUMMARY="$t/summary.md" node "$check" "$t/src") > "$t/out.txt"
  line="$(grep '^::warning title=Factory skills behind::' "$t/out.txt")" || fail "no annotation: $(cat "$t/out.txt")"
  case "$line" in *%0A*) ;; *) fail "newlines not encoded: $line" ;; esac
  grep -q "### Factory skills behind" "$t/summary.md" || fail "no summary"
}

status=0
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  if (set -e; "$t"); then echo "ok   $t"; else echo "FAIL $t"; status=1; fi
done
exit "$status"
