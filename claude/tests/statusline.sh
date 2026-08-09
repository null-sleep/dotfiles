#!/bin/sh
# Deterministic smoke/boundary tests for both statusline forks.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME"
ESC=$(printf '\033')
strip() { sed "s/${ESC}\\[[0-9;]*m//g"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

CLAUDE='{"session_id":"s","model":{"display_name":"Opus (1M context)"},"context_window":{"used_percentage":75,"current_usage":{"input_tokens":100,"cache_read_input_tokens":800,"cache_creation_input_tokens":100}},"fast_mode":true,"effort":{"level":"high"},"rate_limits":{"five_hour":{"used_percentage":55},"seven_day":{"used_percentage":10}}}'
CURSOR_WIDE='{"session_id":"c","model":{"display_name":"Auto (1M context)"},"render_width_chars":80,"context_window":{"used_percentage":54,"current_usage":{"input_tokens":100,"cache_read_input_tokens":800,"cache_creation_input_tokens":100}}}'
CURSOR='{"session_id":"c","model":{"display_name":"Auto (1M context)"},"render_width_chars":12,"context_window":{"used_percentage":54,"current_usage":{"input_tokens":100,"cache_read_input_tokens":800,"cache_creation_input_tokens":100}}}'

wide=$(printf '%s' "$CLAUDE" | COLUMNS=120 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
printf '%s' "$wide" | grep -q 'Opus \[1M\].*⚡hi.*ctx:75%.*CH80%.*#1.*5h:55%.*7d:10%' || fail "wide Claude segments"

# Pruning must work under macOS /bin/sh and BSD find (no GNU -mmin/-maxdepth).
printf '1\n' >"$XDG_CACHE_HOME/claude-statusline/growth-stale"
touch -t 202001010000 "$XDG_CACHE_HOME/claude-statusline/growth-stale"
printf '%s' "$CLAUDE" | COLUMNS=120 sh "$ROOT/claude/.claude/statusline-command.sh" >/dev/null
[ ! -e "$XDG_CACHE_HOME/claude-statusline/growth-stale" ] || fail "Claude stale-history pruning"

narrow=$(printf '%s' "$CLAUDE" | COLUMNS=20 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
[ "$narrow" = 'ctx:75%' ] || fail "Claude narrow retention: $narrow"

diag=$(printf '%s' "$CLAUDE" | COLUMNS=20 sh "$ROOT/claude/.claude/statusline-command.sh" --status)
printf '%s' "$diag" | grep -q '^shed limit7 flag msgs cache limit5 model$' || fail "Claude shed order"
printf '%s' "$diag" | grep -q 'segment flag .*width=4.*measured=3' || fail "wide glyph diagnostic"

cursor_wide=$(printf '%s' "$CURSOR_WIDE" | sh "$ROOT/cursor/.cursor/statusline-command.sh" | strip)
printf '%s' "$cursor_wide" | grep -q 'Auto \[1M\].*ctx:54%.*CH80%.*#1' || fail "wide Cursor segments: $cursor_wide"

# Cache-hit rate rounds half up (87.5% -> 88%), not floors (-> 87%), matching
# the pi footer's Math.round so the three forks agree at the boundary.
CACHE_HALF='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":1,"current_usage":{"input_tokens":25,"cache_read_input_tokens":175,"cache_creation_input_tokens":0}}}'
cache_half_claude=$(printf '%s' "$CACHE_HALF" | COLUMNS=120 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
printf '%s' "$cache_half_claude" | grep -q 'CH88%' || fail "Claude cache-hit rounding: $cache_half_claude"
cache_half_cursor=$(printf '%s' "$CACHE_HALF" | sh "$ROOT/cursor/.cursor/statusline-command.sh" | strip)
printf '%s' "$cache_half_cursor" | grep -q 'CH88%' || fail "Cursor cache-hit rounding: $cache_half_cursor"

printf '1\n' >"$XDG_CACHE_HOME/cursor-statusline/growth-stale"
touch -t 202001010000 "$XDG_CACHE_HOME/cursor-statusline/growth-stale"
printf '%s' "$CURSOR_WIDE" | sh "$ROOT/cursor/.cursor/statusline-command.sh" >/dev/null
[ ! -e "$XDG_CACHE_HOME/cursor-statusline/growth-stale" ] || fail "Cursor stale-history pruning"

cursor=$(printf '%s' "$CURSOR" | sh "$ROOT/cursor/.cursor/statusline-command.sh" | strip)
# render_width_chars=12 retains ctx only (same shed priority as Claude's left cluster).
[ "$cursor" = 'ctx:54%' ] || fail "Cursor width shedding: $cursor"

cursor_diag=$(printf '%s' "$CURSOR" | sh "$ROOT/cursor/.cursor/statusline-command.sh" --status)
printf '%s' "$cursor_diag" | grep -q '^shed msgs cache model$' || fail "Cursor shed order"

# A second distinct sample produces a one-cell bar, which sheds before messages.
BARS1='{"session_id":"bars","model":{"display_name":"Auto"},"context_window":{"used_percentage":10,"current_usage":{"input_tokens":100}}}'
BARS2='{"session_id":"bars","model":{"display_name":"Auto"},"context_window":{"used_percentage":10,"current_usage":{"input_tokens":200}}}'
printf '%s' "$BARS1" | COLUMNS=80 sh "$ROOT/claude/.claude/statusline-command.sh" >/dev/null
bars=$(printf '%s' "$BARS2" | COLUMNS=80 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
printf '%s' "$bars" | grep -Eq '#2 [▁▂▃▄▅▆▇█]' || fail "sparkline render: $bars"

# Backslashes from payload text are data, not a second printf format language.
slash=$(printf '%s' '{"model":{"display_name":"A\\cB"}}' | sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
[ "$slash" = 'A\cB' ] || fail "literal model backslash: $slash"

# Piped diagnostics do not create state when no cache exists.
rm -rf "$XDG_CACHE_HOME"
printf '{}' | sh "$ROOT/cursor/.cursor/statusline-command.sh" --status >/dev/null
[ ! -e "$XDG_CACHE_HOME/cursor-statusline" ] || fail "diagnostic wrote state"

empty=$(printf '{}' | COLUMNS=20 sh "$ROOT/claude/.claude/statusline-command.sh")
[ -z "$empty" ] || fail "empty payload"

# Byte-oriented locales must not change declared flag fit behavior.
locale_c=$(printf '%s' "$CLAUDE" | LC_ALL=C COLUMNS=20 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
locale_utf8=$(printf '%s' "$CLAUDE" | LC_ALL=en_US.UTF-8 COLUMNS=20 sh "$ROOT/claude/.claude/statusline-command.sh" | strip)
[ "$locale_c" = "$locale_utf8" ] || fail "locale-dependent fit"

printf 'statusline tests: ok\n'
