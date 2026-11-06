#!/usr/bin/env bash
# Copies the factory's stage skills from a factory-skills checkout into this
# repo, and records the commit they came from in .agents/factory-skills.json.
#
# Usage: scripts/sync-factory-skills.sh <path to factory-skills checkout>
#
# The skills land in .agents/skills/, with links from .claude/skills/ so
# Claude Code finds them too. factory-repo-setup isn't copied: a repo only
# needs it once. Commit the result.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path to factory-skills checkout>" >&2
  exit 2
fi

src="$(cd "$1" && pwd)"
root="$(git rev-parse --show-toplevel)"

if [ ! -d "$src/skills/factory-orchestrator" ]; then
  echo "No factory skills in $src/skills" >&2
  exit 1
fi

# A pin is only useful if the commit it names holds exactly what was copied.
if [ -n "$(git -C "$src" status --porcelain -- skills)" ]; then
  echo "$src has uncommitted changes under skills/. Commit them first." >&2
  exit 1
fi

commit="$(git -C "$src" rev-parse HEAD)"
remote="$(git -C "$src" remote get-url origin 2>/dev/null || echo "")"

mkdir -p "$root/.agents/skills" "$root/.claude/skills"

# Drop the previous copy, so skills removed upstream go away here too.
rm -rf "$root"/.agents/skills/factory-* "$root"/.claude/skills/factory-*

names=()
for dir in "$src"/skills/factory-*/; do
  name="$(basename "$dir")"
  [ "$name" = "factory-repo-setup" ] && continue
  cp -R "${dir%/}" "$root/.agents/skills/$name"
  ln -s "../../.agents/skills/$name" "$root/.claude/skills/$name"
  names+=("\"$name\"")
done

cat > "$root/.agents/factory-skills.json" <<JSON
{
  "source": "$remote",
  "commit": "$commit",
  "skills": [$(IFS=,; echo "${names[*]}" | sed 's/,/, /g')]
}
JSON

echo "Synced ${#names[@]} skills from ${remote:-$src} at ${commit:0:7}"
