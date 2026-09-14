#!/bin/bash
# Behavioral test for setup-review-pr.sh using an isolated fresh HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SETUP="$ROOT/claude/setup-review-pr.sh"
REPO_SKILL="$ROOT/agents/.agents/skills/review-pr"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
HOME_DIR="$TMP/home"
CANONICAL="$HOME_DIR/.agents/skills/review-pr"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$CANONICAL"
ln -s "$REPO_SKILL/SKILL.generic.md" "$CANONICAL/SKILL.generic.md"

HOME="$HOME_DIR" "$SETUP" >/dev/null
[ "$(readlink "$CANONICAL/SKILL.md")" = "SKILL.generic.md" ] \
  || fail "generic selection failed"
for host in .claude .codex; do
  target="$HOME_DIR/$host/skills/review-pr"
  [ -L "$target" ] || fail "$host compatibility link was not created"
  [ "$(realpath "$target")" = "$(realpath "$CANONICAL")" ] \
    || fail "$host compatibility link does not resolve to the canonical skill"
done
HOME="$HOME_DIR" "$SETUP" >/dev/null || fail "idempotent rerun failed"

# Preserve a pre-existing real skill by quarantining it before linking ours.
rm "$HOME_DIR/.codex/skills/review-pr"
mkdir "$HOME_DIR/.codex/skills/review-pr"
printf 'keep\n' > "$HOME_DIR/.codex/skills/review-pr/sentinel"
HOME="$HOME_DIR" "$SETUP" >/dev/null
[ "$(cat "$HOME_DIR/.codex/skills/review-pr.disabled/sentinel")" = keep ] \
  || fail "pre-existing Codex skill was not preserved"
[ "$(realpath "$HOME_DIR/.codex/skills/review-pr")" = "$(realpath "$CANONICAL")" ] \
  || fail "Codex compatibility link was not restored after quarantine"

printf 'review-pr tests: ok\n'
