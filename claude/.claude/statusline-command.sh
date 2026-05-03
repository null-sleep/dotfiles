#!/bin/sh
# Claude Code status line — model, context %, and per-message context growth bars
# Input: JSON from stdin

input=$(cat)

# Parse all top-level fields in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "branch=\(.worktree.branch // "")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "cost=\(.cost.total_cost_usd // "")",
  @sh "cwd=\(.workspace.current_dir // .cwd // "")"
')"

# Compute last-message cost from delta of cumulative session cost
last_msg_cost=""
if [ -n "$session_id" ] && [ -n "$cost" ] && [ "$cost" != "0" ]; then
  PREV_COST_FILE="/tmp/claude-ctx-prevcost-${session_id}"
  prev_cost=$(cat "$PREV_COST_FILE" 2>/dev/null || echo "0")
  last_msg_cost=$(awk -v c="$cost" -v p="$prev_cost" 'BEGIN { printf "%.2f", c - p }')
  echo "$cost" > "$PREV_COST_FILE"
fi

# Current context size: input_tokens from the latest API call
# This grows each message because the full conversation is resent
current_input=$(echo "$input" | jq -r '
  .context_window.current_usage
  | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
')

# --- Context growth tracking ---
HISTORY_FILE="/tmp/claude-ctx-growth-${session_id}"
bars=""

# Clean up history files from old sessions (>7d), at most once per hour
CLEANUP_STAMP="/tmp/claude-ctx-cleanup-stamp"
if [ ! -f "$CLEANUP_STAMP" ] || [ "$(find "$CLEANUP_STAMP" -mmin +60 2>/dev/null)" ]; then
  find /tmp -maxdepth 1 \( -name 'claude-ctx-growth-*' -o -name 'claude-ctx-prevcost-*' \) -mtime +7 -delete 2>/dev/null
  touch "$CLEANUP_STAMP"
fi

if [ -n "$session_id" ] && [ -n "$current_input" ] && [ "$current_input" != "null" ] && [ "$current_input" -gt 0 ] 2>/dev/null; then
  # Append current snapshot (deduplicate: only if different from last line)
  last_val=$(tail -1 "$HISTORY_FILE" 2>/dev/null || echo "")
  if [ "$last_val" != "$current_input" ]; then
    echo "$current_input" >> "$HISTORY_FILE"
  fi

  msg_count=$(wc -l < "$HISTORY_FILE" | tr -d ' ')

  # Read all snapshots, compute deltas, render bars
  # Uses awk to: compute deltas, normalize to bar heights, pick unicode block chars
  bars=$(awk '
    BEGIN { n = 0 }
    { vals[n++] = $1 }
    END {
      if (n < 2) exit

      # Compute deltas (how much context grew per message)
      nd = 0
      for (i = 1; i < n; i++) {
        d = vals[i] - vals[i-1]
        if (d < 0) d = 0
        deltas[nd++] = d
      }
      if (nd == 0) exit

      # Show last 15 deltas max (keep it compact)
      start = 0
      if (nd > 15) start = nd - 15

      # Find max delta for normalization (only within displayed window)
      max = 0
      for (i = start; i < nd; i++) {
        if (deltas[i] > max) max = deltas[i]
      }
      if (max == 0) exit

      # Unicode block elements: 8 levels from empty to full
      # ▁▂▃▄▅▆▇█
      split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", blocks, " ")

      result = ""
      for (i = start; i < nd; i++) {
        # Normalize to 1-8 range
        level = int((deltas[i] / max) * 7) + 1
        if (level > 8) level = 8
        if (level < 1) level = 1
        result = result blocks[level]
      }
      printf "%s", result
    }
  ' "$HISTORY_FILE")
fi

# --- Monthly cost tracking ---
COST_DIR="$HOME/.claude/cost-log"
monthly_cost=""

if [ -n "$session_id" ] && [ -n "$cost" ] && [ "$cost" != "0" ]; then
  mkdir -p "$COST_DIR"
  MONTH_FILE="$COST_DIR/$(date +%Y-%m).tsv"

  # Update this session's line (replace if exists, append if not)
  if [ -f "$MONTH_FILE" ] && grep -q "^${session_id}	" "$MONTH_FILE" 2>/dev/null; then
    awk -v sid="$session_id" -v c="$cost" -F'\t' 'BEGIN{OFS="\t"} $1==sid{$2=c}{print}' "$MONTH_FILE" > "${MONTH_FILE}.tmp" && mv "${MONTH_FILE}.tmp" "$MONTH_FILE"
  else
    printf '%s\t%s\n' "$session_id" "$cost" >> "$MONTH_FILE"
  fi

  # Sum all sessions for monthly total
  monthly_cost=$(awk -F'\t' '{ sum += $2 } END { printf "%.2f", sum }' "$MONTH_FILE")
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

if [ -n "$branch" ]; then
  if [ -n "$line" ]; then
    line=$(printf "%s  branch:%s" "$line" "$branch")
  else
    line=$(printf "branch:%s" "$branch")
  fi
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  # Color the percentage based on usage
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

# Append session cost and monthly total
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  cost_fmt=$(printf '$%.2f' "$cost")
  msg_cost_part=""
  if [ -n "$last_msg_cost" ] && [ "$last_msg_cost" != "0.00" ]; then
    msg_cost_part=$(printf ' +$%s' "$last_msg_cost")
  fi
  if [ -n "$monthly_cost" ]; then
    line=$(printf "%s  ${dim}%s%s (mo:\$%s)${reset}" "$line" "$cost_fmt" "$msg_cost_part" "$monthly_cost")
  else
    line=$(printf "%s  ${dim}%s%s${reset}" "$line" "$cost_fmt" "$msg_cost_part")
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
