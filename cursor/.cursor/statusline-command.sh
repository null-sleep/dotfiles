#!/bin/sh
# =============================================================================
# Cursor CLI status line  —  fork of claude/.claude/statusline-command.sh
# =============================================================================
#     Auto  ctx:54%  #2 ▁▂▃
#
# Segments: .model.display_name (cyan) / .context_window.used_percentage
# (red≥90 yellow≥70 else dim) / message count / per-message context-growth bars
# (last ≤15). No branch (dropped 2026-07-22; cwd/git still in the payload — see
# git history to revive). Trimmed to Cursor's thinner payload; this header is
# the only reference (the design plan was deleted at ship), so keep it current.
#
# WIRING: the statusLine block in ~/.cursor/cli-config.json runs
#   "bash /Users/<you>/.cursor/statusline-command.sh" with "padding": 2.
#   Injected by cursor/setup-statusline.sh (run after `stow --no-folding
#   cursor`); cli-config.json is machine-local, not stowed. cursor-agent reads
#   statusLine at session START — restart to see edits.
#   GOTCHA: Cursor does NOT expand $HOME in the command (Claude does), so a
#   "bash $HOME/..." command renders blank — setup injects an absolute path.
#
# PAYLOAD (JSON on stdin, per refresh — fires many times per message, so the
# sparkline dedups unchanged context; captured live 2026.07.20). Used fields:
#   .session_id                       sparkline history key
#   .model.display_name               model segment ("Auto")
#   .context_window.used_percentage   ctx% — a FLOAT (5.8), round %.0f
#   .context_window.current_usage     sparkline = input + cache_creation + cache_read
#   Present but unused: cwd, render_width_chars (term width; future trim),
#   transcript_path, workspace, session_name, output_style, version, autorun,
#   context_window.{context_window_size,total_*,remaining_percentage}.
#
# NOT sent by Cursor (so no such segment): cost / rate_limits (Claude/Anthropic
#   only) and model.param_summary (model is only {id,display_name}); branch's
#   worktree.branch isn't sent either — moot, we don't show branch. NO
#   usage/quota is possible (checked 2026-07-22): nothing in the payload,
#   `cursor-agent about` gives only a static "Subscription Tier" via a slow
#   network call, no local cache holds a live quota — free-plan usage lives only
#   in Cursor's web dashboard.
#
# STATE: per-session sparkline history in $STATE_DIR (~/.cache, not world-shared
#   /tmp), pruned after 7d.  Input: JSON on stdin.
# =============================================================================

input=$(cat)

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cursor-statusline"
mkdir -p "$STATE_DIR"

# Parse the fields we use in a single jq call. Cursor has no worktree.branch,
# so branch is derived from cwd via git below.
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "session_id=\(.session_id // "")"
')"

# Current context size: input_tokens from the latest API call (matches Claude's
# formula). Grows each message because the full conversation is resent.
current_input=$(echo "$input" | jq -r '
  .context_window.current_usage
  | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
')

# --- Context growth tracking ---
HISTORY_FILE="$STATE_DIR/growth-${session_id}"
bars=""
msg_count=""

# Clean up history files from old sessions (>7d), at most once per hour
CLEANUP_STAMP="$STATE_DIR/cleanup-stamp"
if [ ! -f "$CLEANUP_STAMP" ] || [ "$(find "$CLEANUP_STAMP" -mmin +60 2>/dev/null)" ]; then
  find "$STATE_DIR" -maxdepth 1 -name 'growth-*' -mtime +7 -delete 2>/dev/null
  touch "$CLEANUP_STAMP"
fi

if [ -n "$session_id" ] && [ -n "$current_input" ] && [ "$current_input" != "null" ] && [ "$current_input" -gt 0 ] 2>/dev/null; then
  last_val=$(tail -1 "$HISTORY_FILE" 2>/dev/null || echo "")
  if [ "$last_val" != "$current_input" ]; then
    echo "$current_input" >> "$HISTORY_FILE"
  fi

  msg_count=$(wc -l < "$HISTORY_FILE" | tr -d ' ')

  bars=$(awk '
    BEGIN { n = 0 }
    { vals[n++] = $1 }
    END {
      if (n < 2) exit

      nd = 0
      for (i = 1; i < n; i++) {
        d = vals[i] - vals[i-1]
        if (d < 0) d = 0
        deltas[nd++] = d
      }
      if (nd == 0) exit

      start = 0
      if (nd > 15) start = nd - 15

      max = 0
      for (i = start; i < nd; i++) {
        if (deltas[i] > max) max = deltas[i]
      }
      if (max == 0) exit

      split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", blocks, " ")

      result = ""
      for (i = start; i < nd; i++) {
        level = int((deltas[i] / max) * 7) + 1
        if (level > 8) level = 8
        if (level < 1) level = 1
        result = result blocks[level]
      }
      printf "%s", result
    }
  ' "$HISTORY_FILE")
fi

# --- ANSI colors ---
cyan='\033[0;36m'
dim='\033[2m'
yellow='\033[0;33m'
red='\033[0;31m'
reset='\033[0m'

# --- Build output line ---
line=""

if [ -n "$model" ]; then
  line=$(printf "${cyan}%s${reset}" "$model")
fi

if [ -n "$used" ]; then
  # used_percentage is a float (e.g. 5.8) — round to a whole percent
  used_int=$(printf "%.0f" "$used")
  if [ "$used_int" -ge 90 ]; then
    pct_color="$red"
  elif [ "$used_int" -ge 70 ]; then
    pct_color="$yellow"
  else
    pct_color="$dim"
  fi
  if [ -n "$line" ]; then
    line=$(printf "%s  ctx:${pct_color}%s%%${reset}" "$line" "$used_int")
  else
    line=$(printf "ctx:${pct_color}%s%%${reset}" "$used_int")
  fi
fi

# Append message count and growth bars
if [ -n "$msg_count" ] && [ "$msg_count" -gt 0 ] 2>/dev/null; then
  line=$(printf "%s  ${dim}#%s${reset}" "$line" "$msg_count")
  if [ -n "$bars" ]; then
    line=$(printf "%s ${dim}%s${reset}" "$line" "$bars")
  fi
fi

printf "%b\n" "$line"
