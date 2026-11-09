#!/usr/bin/env bash
# The test_ functions run through declare -F at the end.
# shellcheck disable=SC2329
# Tests for the stack-urls.mjs and smoke.mjs templates, which a set-up repo
# runs on the outputs file `cdk deploy --outputs-file` writes.
set -euo pipefail

templates="$(cd "$(dirname "$0")/.." && pwd)/skills/factory-repo-setup/templates"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts"
cp "$templates/stack-urls.mjs" "$templates/smoke.mjs" "$work/scripts/"
cd "$work"

fail() {
  echo "  $*" >&2
  exit 1
}

test_lists_only_url_outputs() {
  cat > outputs.json <<'JSON'
{"App-dev-x": {"UrlApi": "https://api.example.com/", "TableName": "t", "UrlNotes": "not a url"},
 "Other": {"UrlSite": "http://site.example.com/"}}
JSON
  got="$(node scripts/stack-urls.mjs outputs.json)"
  want="$(printf 'https://api.example.com/\nhttp://site.example.com/')"
  [ "$got" = "$want" ] || fail "got: $got"
}

test_smoke_passes_with_no_urls() {
  echo '{"App": {"TableName": "t"}}' > outputs.json
  node scripts/smoke.mjs outputs.json | grep -q "nothing to smoke-test" || fail "no message"
}

test_smoke_fails_when_a_url_is_down() {
  # Port 9 (discard) refuses connections on a runner.
  echo '{"App": {"Url": "http://127.0.0.1:9/"}}' > outputs.json
  if node scripts/smoke.mjs outputs.json > out.txt; then fail "passed: $(cat out.txt)"; fi
  grep -q "^FAIL" out.txt || fail "no FAIL line: $(cat out.txt)"
}

test_requires_an_outputs_file() {
  if node scripts/smoke.mjs 2> err.txt; then fail "ran without a file"; fi
  grep -q usage err.txt || fail "no usage"
}

status=0
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  if (set -e; "$t"); then echo "ok   $t"; else echo "FAIL $t"; status=1; fi
done
exit "$status"
