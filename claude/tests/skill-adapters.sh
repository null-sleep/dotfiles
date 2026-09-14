#!/bin/bash
# Behavioral test for setup-skill-adapters.sh using an isolated fresh HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SETUP="$ROOT/claude/setup-skill-adapters.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
HOME_DIR="$TMP/home"
CANONICAL="$HOME_DIR/.agents/skills"
CLAUDE="$HOME_DIR/.claude/skills"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$CANONICAL/alpha" "$CANONICAL/beta" \
  "$CANONICAL/review-pr" "$CANONICAL/review-pr.disabled" "$CANONICAL/not-a-skill"
printf '%s\n' '---' 'description: alpha' '---' > "$CANONICAL/alpha/SKILL.md"
printf '%s\n' '---' 'description: beta' '---' > "$CANONICAL/beta/skill.md"
printf '%s\n' '---' 'description: selected separately' '---' > "$CANONICAL/review-pr/SKILL.md"
printf '%s\n' '---' 'description: quarantined' '---' > "$CANONICAL/review-pr.disabled/SKILL.md"

HOME="$HOME_DIR" "$SETUP" >/dev/null
[ -d "$CLAUDE" ] || fail "fresh HOME did not get ~/.claude/skills"
for name in alpha beta; do
  [ -L "$CLAUDE/$name" ] || fail "$name was not linked"
  [ "$(realpath "$CLAUDE/$name")" = "$(realpath "$CANONICAL/$name")" ] \
    || fail "$name does not resolve to its canonical skill"
done
[ ! -e "$CLAUDE/review-pr" ] || fail "review-pr must remain owned by setup-review-pr.sh"
[ ! -e "$CLAUDE/review-pr.disabled" ] || fail "quarantined skill was exposed"
[ ! -e "$CLAUDE/not-a-skill" ] || fail "directory without skill instructions was exposed"

HOME="$HOME_DIR" "$SETUP" >/dev/null || fail "idempotent rerun failed"

rm "$CLAUDE/beta"
mkdir "$CLAUDE/beta"
printf 'keep\n' > "$CLAUDE/beta/sentinel"
if HOME="$HOME_DIR" "$SETUP" >/dev/null 2>&1; then
  fail "real Claude skill path was overwritten"
fi
[ "$(cat "$CLAUDE/beta/sentinel")" = keep ] || fail "conflicting path contents changed"

printf 'skill-adapter tests: ok\n'
