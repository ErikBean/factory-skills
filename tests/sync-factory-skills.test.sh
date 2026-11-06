#!/usr/bin/env bash
# Tests for skills/factory-repo-setup/templates/sync-factory-skills.sh.
# Each test builds a fake factory-skills checkout and a target repo in a
# temporary folder, runs the script in the target, and checks the result.
set -euo pipefail

sync="$(cd "$(dirname "$0")/.." && pwd)/skills/factory-repo-setup/templates/sync-factory-skills.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Each test runs in its own subshell, so a failed check or an unexpected
# error ends only that test.
fail() {
  echo "  $*" >&2
  exit 1
}

# Makes a factory-skills checkout at $1 with a committed skill per extra arg.
make_source() {
  local src="$1"; shift
  git init -q "$src"
  git -C "$src" remote add origin https://github.com/example/factory-skills
  for name in "$@"; do
    mkdir -p "$src/skills/$name/references"
    echo "# $name" > "$src/skills/$name/SKILL.md"
    echo "ref" > "$src/skills/$name/references/notes.md"
  done
  git -C "$src" add -A
  git -C "$src" commit -qm "skills"
}

make_target() {
  git init -q "$1"
}

# Reads a key from the target's pin file.
pin() {
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(" ".join(v) if isinstance(v, list) else v)' \
    "$1/.agents/factory-skills.json" "$2"
}

test_copies_and_links_stage_skills() {
  local src="$work/1/src" dst="$work/1/dst"
  make_source "$src" factory-orchestrator factory-implementer factory-repo-setup
  make_target "$dst"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  for name in factory-orchestrator factory-implementer; do
    [ -f "$dst/.agents/skills/$name/SKILL.md" ] || fail "$name not copied"
    [ -f "$dst/.agents/skills/$name/references/notes.md" ] || fail "$name subfolders not copied"
    [ -L "$dst/.agents/skills/$name" ] && fail "$name copied as a link, not a folder"
    [ "$(readlink "$dst/.claude/skills/$name")" = "../../.agents/skills/$name" ] \
      || fail "$name not linked relatively from .claude/skills"
    [ -f "$dst/.claude/skills/$name/SKILL.md" ] || fail "$name link doesn't resolve"
  done
}

test_skips_repo_setup() {
  local src="$work/2/src" dst="$work/2/dst"
  make_source "$src" factory-orchestrator factory-repo-setup
  make_target "$dst"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  [ -e "$dst/.agents/skills/factory-repo-setup" ] && fail "factory-repo-setup copied"
  [ -e "$dst/.claude/skills/factory-repo-setup" ] && fail "factory-repo-setup linked"
  return 0
}

test_writes_pin_file() {
  local src="$work/3/src" dst="$work/3/dst"
  make_source "$src" factory-orchestrator factory-implementer factory-repo-setup
  make_target "$dst"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  [ "$(pin "$dst" commit)" = "$(git -C "$src" rev-parse HEAD)" ] || fail "wrong commit"
  [ "$(pin "$dst" source)" = "https://github.com/example/factory-skills" ] || fail "wrong source"
  [ "$(pin "$dst" skills)" = "factory-implementer factory-orchestrator" ] \
    || fail "wrong skills: $(pin "$dst" skills)"
}

test_rerun_updates_and_removes_dropped_skills() {
  local src="$work/4/src" dst="$work/4/dst"
  make_source "$src" factory-orchestrator factory-implementer factory-reviewer
  make_target "$dst"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  git -C "$src" rm -rq skills/factory-reviewer
  echo "# changed" > "$src/skills/factory-orchestrator/SKILL.md"
  git -C "$src" commit -qam "drop reviewer"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  [ -e "$dst/.agents/skills/factory-reviewer" ] && fail "dropped skill still copied"
  [ -L "$dst/.claude/skills/factory-reviewer" ] && fail "dropped skill still linked"
  [ "$(cat "$dst/.agents/skills/factory-orchestrator/SKILL.md")" = "# changed" ] || fail "skill not updated"
  [ "$(pin "$dst" commit)" = "$(git -C "$src" rev-parse HEAD)" ] || fail "commit not updated"
  [ "$(pin "$dst" skills)" = "factory-implementer factory-orchestrator" ] \
    || fail "wrong skills: $(pin "$dst" skills)"
}

test_leaves_other_skills_alone() {
  local src="$work/5/src" dst="$work/5/dst"
  make_source "$src" factory-orchestrator
  make_target "$dst"
  mkdir -p "$dst/.agents/skills/my-skill" "$dst/.claude/skills/other-skill"
  (cd "$dst" && "$sync" "$src" > /dev/null)

  [ -d "$dst/.agents/skills/my-skill" ] || fail "removed a skill it doesn't own from .agents"
  [ -d "$dst/.claude/skills/other-skill" ] || fail "removed a skill it doesn't own from .claude"
}

test_works_from_a_subfolder() {
  local src="$work/6/src" dst="$work/6/dst"
  make_source "$src" factory-orchestrator
  make_target "$dst"
  mkdir -p "$dst/scripts"
  (cd "$dst/scripts" && "$sync" "$src" > /dev/null)

  [ -f "$dst/.agents/skills/factory-orchestrator/SKILL.md" ] || fail "didn't sync into the repo root"
}

test_refuses_uncommitted_changes() {
  local src="$work/7/src" dst="$work/7/dst"
  make_source "$src" factory-orchestrator factory-implementer
  make_target "$dst"
  (cd "$dst" && "$sync" "$src" > /dev/null)
  local before; before="$(pin "$dst" commit)"

  echo "edit" >> "$src/skills/factory-orchestrator/SKILL.md"
  local err status=0
  err="$(cd "$dst" && "$sync" "$src" 2>&1 > /dev/null)" || status=$?
  [ "$status" -ne 0 ] || fail "accepted a modified skill"
  [[ "$err" == *"uncommitted changes under skills/"* ]] || fail "unclear error: $err"
  [ "$(pin "$dst" commit)" = "$before" ] || fail "pin changed after refusing"
  [ -f "$dst/.agents/skills/factory-implementer/SKILL.md" ] || fail "copy removed after refusing"

  git -C "$src" checkout -q -- skills
  mkdir "$src/skills/factory-new" && echo "# new" > "$src/skills/factory-new/SKILL.md"
  status=0
  (cd "$dst" && "$sync" "$src" > /dev/null 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "accepted an untracked skill"
}

test_ignores_changes_outside_skills() {
  local src="$work/8/src" dst="$work/8/dst"
  make_source "$src" factory-orchestrator
  make_target "$dst"
  echo "draft" > "$src/README.md"
  (cd "$dst" && "$sync" "$src" > /dev/null) || fail "refused changes outside skills/"
}

test_rejects_bad_arguments() {
  local dst="$work/9/dst" status
  make_target "$dst"
  mkdir -p "$work/9/empty"

  status=0; (cd "$dst" && "$sync" > /dev/null 2>&1) || status=$?
  [ "$status" -eq 2 ] || fail "no argument: exit $status, want 2"

  status=0; (cd "$dst" && "$sync" "$work/9/empty" > /dev/null 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail "accepted a folder with no factory skills"
  [ -e "$dst/.agents" ] && fail "wrote files for a folder with no factory skills"
  return 0
}

failures=0
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  # errexit is ignored inside `if ( ... )`, so turn it off out here instead.
  set +e
  (set -e; "$t")
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "ok   $t"
  else
    echo "FAIL $t"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
