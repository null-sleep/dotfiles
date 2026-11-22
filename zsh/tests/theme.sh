#!/bin/bash
# Exercise the switcher with isolated state and stubbed macOS commands.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
THEME="$ROOT/zsh/.local/bin/theme"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export HOME="$TMP/home" XDG_DATA_HOME="$TMP/data" MOCK_LOG="$TMP/macos.log"
export PATH="$TMP/bin:$PATH"
CLAUDE="$HOME/.claude/themes"
NVIM="$XDG_DATA_HOME/nvim/theme.txt"
mkdir -p "$TMP/bin" "$CLAUDE" "$(dirname "$NVIM")"

cat >"$TMP/bin/defaults" <<'EOF'
#!/bin/sh
printf 'defaults %s\n' "$*" >>"$MOCK_LOG"
[ "$1" != read ] || printf 'Dark\n'
EOF
cat >"$TMP/bin/osascript" <<'EOF'
#!/bin/sh
printf 'osascript %s\n' "$*" >>"$MOCK_LOG"
EOF
chmod +x "$TMP/bin/defaults" "$TMP/bin/osascript"
for palette in dracula catppuccin-latte; do
  cp "$ROOT/claude/.claude/themes/$palette.json" "$CLAUDE/$palette.json"
done

fail() { echo "FAIL: $*" >&2; exit 1; }
reset_state() {
  cp "$CLAUDE/catppuccin-latte.json" "$CLAUDE/active.json"
  printf 'catppuccin-latte\n' >"$NVIM"
  : >"$MOCK_LOG"
}
assert_state() {
  local selected="$1"
  if [ "$selected" = claude ] || [ "$selected" = all ]; then
    cmp -s "$CLAUDE/active.json" "$CLAUDE/dracula.json" || fail 'Claude did not switch'
  else
    cmp -s "$CLAUDE/active.json" "$CLAUDE/catppuccin-latte.json" || fail 'Claude changed unexpectedly'
  fi
  if [ "$selected" = nvim ] || [ "$selected" = all ]; then
    [ "$(cat "$NVIM")" = dracula ] || fail 'Neovim did not switch'
  else
    [ "$(cat "$NVIM")" = catppuccin-latte ] || fail 'Neovim changed unexpectedly'
  fi
}

for target in claude nvim; do
  reset_state
  bash "$THEME" dark --tool "$target" >/dev/null
  assert_state "$target"
  [ ! -s "$MOCK_LOG" ] || fail "$target switch touched macOS"
  bash "$THEME" light --tool "$target" >/dev/null
  cmp -s "$CLAUDE/active.json" "$CLAUDE/catppuccin-latte.json" || fail 'Claude did not return to light'
  [ "$(cat "$NVIM")" = catppuccin-latte ] || fail 'Neovim did not return to light'
  [ ! -s "$MOCK_LOG" ] || fail "$target light switch touched macOS"
done

reset_state
bash "$THEME" --tool=claude dark >/dev/null
assert_state claude
[ ! -s "$MOCK_LOG" ] || fail 'selector before mode touched macOS'

reset_state
TERM_PROGRAM=zed bash "$THEME" dark --tool claude >"$TMP/out" 2>"$TMP/err"
case "$(cat "$TMP/err")" in
  *"Claude sessions launched in Zed"*) ;;
  *) fail 'Zed user was not warned that Claude follows Zed' ;;
esac
assert_state claude
[ ! -s "$MOCK_LOG" ] || fail 'Zed selector touched macOS'

reset_state
for args in 'dark --tool' 'dark --tool=' 'dark --tool unknown' 'auto --tool claude' 'dark --tool claude --tool nvim' 'dark --tool pi' 'dark extra'; do
  # The cases intentionally contain only fixed, whitespace-separated words.
  # shellcheck disable=SC2086
  if bash "$THEME" $args >/dev/null 2>&1; then fail "accepted invalid arguments: $args"; fi
done
if bash "$THEME" dark --tool '' >/dev/null 2>&1; then fail 'accepted empty target'; fi
assert_state none
[ ! -s "$MOCK_LOG" ] || fail 'invalid arguments touched macOS'

reset_state
mv "$CLAUDE/dracula.json" "$CLAUDE/dracula.json.bak"
if bash "$THEME" dark --tool claude >/dev/null 2>&1; then fail 'targeted switch with a missing palette exited 0'; fi
mv "$CLAUDE/dracula.json.bak" "$CLAUDE/dracula.json"
assert_state none

reset_state
bash "$THEME" dark >/dev/null
assert_state all
[ "$(wc -l <"$MOCK_LOG" | tr -d ' ')" = 2 ] || fail 'unified switch did not pin macOS'

printf 'theme tests: ok\n'
