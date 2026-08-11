#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SETUP="$ROOT/claude/setup-settings.sh"
EXPECTED="$ROOT/claude/.claude/settings.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export HOME="$TMP/home"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

reset_home() {
  rm -rf "$HOME"
  mkdir -p "$HOME/.claude"
}

assert_owned_link() {
  [ -L "$HOME/.claude/settings.json" ] || fail "settings is not a symlink"
  [ "$(readlink -f "$HOME/.claude/settings.json")" = "$EXPECTED" ] \
    || fail "settings points at the wrong checkout"
}

reset_home
"$SETUP" >/dev/null
assert_owned_link
[ ! -e "$HOME/tests/statusline.sh" ] || fail "claude/tests leaked through Stow"
"$SETUP" --check >/dev/null

reset_home
jq -S . "$EXPECTED" > "$HOME/.claude/settings.json"
"$SETUP" >/dev/null
assert_owned_link
backups=("$HOME"/.claude/backups/settings.pre-stow.*.json)
[ -f "${backups[0]}" ] || fail "matching regular file was not backed up"

reset_home
printf '{"private":true}\n' > "$HOME/.claude/settings.json"
sha="$(shasum -a 256 "$HOME/.claude/settings.json" | cut -d ' ' -f 1)"
if "$SETUP" >/dev/null 2>&1; then
  fail "divergent regular file migrated without reviewed hash"
fi
[ ! -L "$HOME/.claude/settings.json" ] || fail "divergent file became a link"
grep -q '"private":true' "$HOME/.claude/settings.json" || fail "divergent file changed"

if "$SETUP" --replace-if-sha256 0000000000000000000000000000000000000000000000000000000000000000 \
  >/dev/null 2>&1; then
  fail "incorrect reviewed hash was accepted"
fi
[ ! -L "$HOME/.claude/settings.json" ] || fail "wrong-hash file became a link"

printf '{}\n' > "$HOME/.claude/keybindings.json"
if "$SETUP" --replace-if-sha256 "$sha" >/dev/null 2>&1; then
  fail "Stow conflict unexpectedly succeeded"
fi
[ ! -L "$HOME/.claude/settings.json" ] || fail "failed migration left a link"
grep -q '"private":true' "$HOME/.claude/settings.json" || fail "failed migration did not roll back"
rm "$HOME/.claude/keybindings.json"

"$SETUP" --replace-if-sha256 "$sha" >/dev/null
assert_owned_link
backups=("$HOME"/.claude/backups/settings.pre-stow.*.json)
grep -q '"private":true' "${backups[0]}" || fail "divergent backup was not retained"

reset_home
ln -s "$TMP/foreign/settings.json" "$HOME/.claude/settings.json"
if "$SETUP" --check >/dev/null 2>&1; then
  fail "dangling foreign symlink was accepted"
fi

mkdir -p "$TMP/foreign"
printf '{}\n' > "$TMP/foreign/settings.json"
if "$SETUP" --check >/dev/null 2>&1; then
  fail "foreign checkout symlink was accepted"
fi

reset_home
mkdir "$HOME/.claude/settings.json"
if "$SETUP" >/dev/null 2>&1; then
  fail "directory target was accepted"
fi

printf 'settings stow tests: ok\n'
