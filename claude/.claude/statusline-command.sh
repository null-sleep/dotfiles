#!/bin/sh
# Claude Code status line — model, context %, and per-message context growth bars
# Mode is controlled by CLAUDE_STATUSLINE_MODE env var:
#   cost  → session cost, per-message delta, monthly total (pay-per-use / API)
#   (unset) → 5h/7d rate limit percentages (Max plan)
# Input: JSON from stdin

input=$(cat)

# Parse all top-level fields in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "branch=\(.worktree.branch // "")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "cost=\(.cost.total_cost_usd // "")",
  @sh "rl_5h=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "rl_5h_resets=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl_7d=\(.rate_limits.seven_day.used_percentage // "")"
')"

# --- Cost mode: per-message delta ---
last_msg_cost=""
monthly_cost=""
if [ "$CLAUDE_STATUSLINE_MODE" = "cost" ]; then
  if [ -n "$session_id" ] && [ -n "$cost" ] && [ "$cost" != "0" ]; then
    PREV_COST_FILE="/tmp/claude-ctx-prevcost-${session_id}"
    prev_cost=$(cat "$PREV_COST_FILE" 2>/dev/null || echo "0")
    last_msg_cost=$(awk -v c="$cost" -v p="$prev_cost" 'BEGIN { printf "%.2f", c - p }')
    echo "$cost" > "$PREV_COST_FILE"

    COST_DIR="$HOME/.claude/cost-log"
    mkdir -p "$COST_DIR"
    MONTH_FILE="$COST_DIR/$(date +%Y-%m).tsv"
    if [ -f "$MONTH_FILE" ] && grep -q "^${session_id}	" "$MONTH_FILE" 2>/dev/null; then
      awk -v sid="$session_id" -v c="$cost" -F'\t' 'BEGIN{OFS="\t"} $1==sid{$2=c}{print}' "$MONTH_FILE" > "${MONTH_FILE}.tmp" && mv "${MONTH_FILE}.tmp" "$MONTH_FILE"
    else
      printf '%s\t%s\n' "$session_id" "$cost" >> "$MONTH_FILE"
    fi
    monthly_cost=$(awk -F'\t' '{ sum += $2 } END { printf "%.2f", sum }' "$MONTH_FILE")
  fi
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

# --- Usage mode: 5h reset countdown ---
resets_in=""
if [ "$CLAUDE_STATUSLINE_MODE" != "cost" ]; then
  if [ -n "$rl_5h_resets" ] && [ "$rl_5h_resets" != "0" ]; then
    now=$(date +%s)
    diff=$((rl_5h_resets - now))
    if [ "$diff" -gt 0 ]; then
      h=$((diff / 3600))
      m=$(( (diff % 3600) / 60 ))
      resets_in=$(printf "%dh%02dm" "$h" "$m")
    fi
  fi
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

if [ "$CLAUDE_STATUSLINE_MODE" = "cost" ]; then
  # Cost mode: session total, per-message delta, monthly total
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
else
  # Usage mode: 5h and 7d rate limit percentages
  if [ -n "$rl_5h" ]; then
    rl_5h_int=$(printf "%.0f" "$rl_5h")
    if [ "$rl_5h_int" -ge 80 ]; then
      rl_color="$red"
    elif [ "$rl_5h_int" -ge 50 ]; then
      rl_color="$yellow"
    else
      rl_color="$dim"
    fi
    rl_part=$(printf "${rl_color}%s%%${reset}" "$rl_5h_int")
    if [ -n "$resets_in" ]; then
      rl_part=$(printf "%s${dim}/%s${reset}" "$rl_part" "$resets_in")
    fi
    line=$(printf "%s  5h:%s" "$line" "$rl_part")
  fi

  if [ -n "$rl_7d" ]; then
    rl_7d_int=$(printf "%.0f" "$rl_7d")
    if [ "$rl_7d_int" -ge 80 ]; then
      rl7_color="$red"
    elif [ "$rl_7d_int" -ge 50 ]; then
      rl7_color="$yellow"
    else
      rl7_color="$dim"
    fi
    line=$(printf "%s  7d:${rl7_color}%s%%${reset}" "$line" "$rl_7d_int")
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
