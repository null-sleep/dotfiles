#!/bin/sh
# =============================================================================
# Claude Code status line  —  https://code.claude.com/docs/en/statusline
# =============================================================================
# Usage mode:  Opus 4.8 (1M context)  ctx:22%  #109 ▁▂▃        5h:10%/3h34m  7d:1%
#
# Built as a LEFT cluster ($line: model · ctx:N% · #msgs · sparkline) and a
# RIGHT cluster ($right: 5h/7d limits, or cost) padded flush-right to the edge.
# Segments: .model.display_name (cyan) / ⚡+effort flag (⚡ yellow when .fast_mode
# on, .effort.level as dim shorthand: hi/med/xhi/…) /
# .context_window.used_percentage (red≥90 yellow≥70 else
# dim) / message count / per-message context-growth bars (last ≤15) /
# .rate_limits.{five_hour,seven_day} (usage) or .cost (cost mode).
# Sibling fork for Cursor: cursor/.cursor/statusline-command.sh.
#
# MODE ($CLAUDE_STATUSLINE_MODE): unset → usage (5h/7d %, subscription plans);
#   "cost" → session $ / per-msg delta / month-to-date (API). Right cluster only
#   — the left cluster is identical either way.
#
# WIRING: the statusLine block in ~/.claude/settings.json runs
#   "bash $HOME/.claude/statusline-command.sh" (Claude expands $HOME; Cursor
#   doesn't — hence its absolute path). Injected by claude/setup-statusline.sh;
#   settings.json is machine-local, not stowed.
#
# WIDTH: Claude captures our stdout, so `tput cols` can't see the terminal — it
#   exports $COLUMNS/$LINES instead (v2.1.153+). Right-align pads by $COLUMNS,
#   measuring VISIBLE width (ANSI stripped, wc -m so a 3-byte block ▁ = 1 col);
#   RMARGIN reserves a few cols because Claude truncates ("…") before the true
#   edge. Unknown width / too-full line → 2-space join. Tune RMARGIN if the
#   inset looks off.
#
# PAYLOAD (JSON on stdin; used fields — full schema in the docs):
#   .session_id                       state key (growth + prevcost files)
#   .model.display_name               model segment ("(1M context)" → "[1M]")
#   .context_window.used_percentage   ctx% (round %.0f)
#   .context_window.current_usage     sparkline = input + cache_creation + cache_read
#   .fast_mode, .effort.level         ⚡ + effort flag (after model)
#   .cost.total_cost_usd              cost mode
#   .rate_limits.five_hour.{used_percentage,resets_at}, .seven_day.used_percentage
#   Present but unused: workspace, session_name, transcript_path, version,
#   thinking, exceeds_200k_tokens, output_style.
#
# BRANCH: parsed from .worktree.branch, which the schema renamed to
#   .workspace.git_worktree — so it reads empty and no branch shows. ACCEPTED
#   (decision 2026-07-22, line preferred without branch); don't switch the path
#   unless asked.
#
# STATE: $STATE_DIR (~/.cache, not world-shared /tmp) holds per-session scratch
#   growth-<id> + prevcost-<id>, pruned after 7d. Cost totals persist in
#   ~/.claude/cost-log (data, not scratch).  Input: JSON on stdin.
# =============================================================================

input=$(cat)

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$STATE_DIR"

# Parse all top-level fields in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "branch=\(.worktree.branch // "")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "fast=\(.fast_mode // false)",
  @sh "effort=\(.effort.level // "")",
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
    PREV_COST_FILE="$STATE_DIR/prevcost-${session_id}"
    prev_cost=$(cat "$PREV_COST_FILE" 2>/dev/null || echo "0")
    last_msg_cost=$(awk -v c="$cost" -v p="$prev_cost" 'BEGIN { printf "%.2f", c - p }')
    echo "$cost" > "$PREV_COST_FILE"

    COST_DIR="$HOME/.claude/cost-log"
    mkdir -p "$COST_DIR"
    MONTH_FILE="$COST_DIR/$(date +%Y-%m).tsv"
    if [ -f "$MONTH_FILE" ] && grep -q "^${session_id}	" "$MONTH_FILE" 2>/dev/null; then
      # mktemp, not a fixed .tmp name: two concurrent sessions ending a
      # message together would truncate each other's rewrite mid-mv and drop
      # a row. mv stays atomic; last-writer-wins is fine for a cost counter.
      month_tmp=$(mktemp "${MONTH_FILE}.XXXXXX")
      awk -v sid="$session_id" -v c="$cost" -F'\t' 'BEGIN{OFS="\t"} $1==sid{$2=c}{print}' "$MONTH_FILE" > "$month_tmp" && mv "$month_tmp" "$MONTH_FILE"
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
HISTORY_FILE="$STATE_DIR/growth-${session_id}"
bars=""

# Clean up history files from old sessions (>7d), at most once per hour
CLEANUP_STAMP="$STATE_DIR/cleanup-stamp"
if [ ! -f "$CLEANUP_STAMP" ] || [ "$(find "$CLEANUP_STAMP" -mmin +60 2>/dev/null)" ]; then
  find "$STATE_DIR" -maxdepth 1 \( -name 'growth-*' -o -name 'prevcost-*' \) -mtime +7 -delete 2>/dev/null
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

# Visible (printable) width of a string: strip ANSI SGR codes, then count
# characters — not bytes — so multi-byte sparkline blocks (▁▂▃) count as 1 each.
ESC=$(printf '\033')
vis_width() {
  printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

# --- Build output line ---
# $line is the left cluster (model, branch, ctx, #N, bars); $right is the
# limits/cost cluster, right-aligned to the terminal edge at the end.
line=""
right=""

if [ -n "$model" ]; then
  # Shorten a "(<size> context)" suffix to "[<size>]", e.g.
  # "Opus 4.8 (1M context)" → "Opus 4.8 [1M]". Size is extracted (not hardcoded),
  # and any other name/suffix is left untouched.
  case "$model" in
    *" ("*" context)")
      _size=${model##* (}     # "1M context)"
      _size=${_size%% *}      # "1M"
      model="${model% (*} [${_size}]"
      ;;
  esac
  line=$(printf "${cyan}%s${reset}" "$model")
fi

# Fast-mode / effort flag right after the model: ⚡ (yellow — fast mode costs
# ~3x, so it nags) when fast mode is on, then the reasoning effort level as a
# dim shorthand. Levels: low→lo medium→med high→hi xhigh→xhi max→max
# ultracode→uc; anything else (auto, or a future level) shows as-is.
flag=""
[ "$fast" = "true" ] && flag=$(printf "${yellow}⚡${reset}")
if [ -n "$effort" ]; then
  case "$effort" in
    low)       eff=lo ;;
    medium)    eff=med ;;
    high)      eff=hi ;;
    xhigh)     eff=xhi ;;
    max)       eff=max ;;
    ultracode) eff=uc ;;
    *)         eff=$effort ;;
  esac
  flag=$(printf "%s${dim}%s${reset}" "$flag" "$eff")
fi
if [ -n "$flag" ]; then
  if [ -n "$line" ]; then
    line=$(printf "%s  %s" "$line" "$flag")
  else
    line="$flag"
  fi
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

# Message count and growth bars — grouped with ctx, before the limits/cost block
if [ -n "$msg_count" ] && [ "$msg_count" -gt 0 ] 2>/dev/null; then
  line=$(printf "%s  ${dim}#%s${reset}" "$line" "$msg_count")
  if [ -n "$bars" ]; then
    line=$(printf "%s ${dim}%s${reset}" "$line" "$bars")
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
      right=$(printf "${dim}%s%s (mo:\$%s)${reset}" "$cost_fmt" "$msg_cost_part" "$monthly_cost")
    else
      right=$(printf "${dim}%s%s${reset}" "$cost_fmt" "$msg_cost_part")
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
    right=$(printf "5h:%s" "$rl_part")
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
    if [ -n "$right" ]; then
      right=$(printf "%s  7d:${rl7_color}%s%%${reset}" "$right" "$rl_7d_int")
    else
      right=$(printf "7d:${rl7_color}%s%%${reset}" "$rl_7d_int")
    fi
  fi
fi

# Right-align $right to the edge via $COLUMNS; RMARGIN clears Claude's "…"
# truncation. Unknown width or too-full line → 2-space join. (Why: header WIDTH.)
COLS="${COLUMNS:-0}"
case "$COLS" in ''|*[!0-9]*) COLS=0 ;; esac
RMARGIN=3

if [ -n "$right" ]; then
  if [ "$COLS" -gt 0 ]; then
    # ⚡ renders 2 cols wide but wc -m counts it as 1 char — correct by +1.
    wide=0; case "$line" in *"⚡"*) wide=1 ;; esac
    gap=$(( COLS - $(vis_width "$line") - wide - $(vis_width "$right") - RMARGIN ))
    if [ "$gap" -ge 2 ]; then
      line=$(printf "%s%*s%s" "$line" "$gap" "" "$right")
    else
      line=$(printf "%s  %s" "$line" "$right")
    fi
  else
    line=$(printf "%s  %s" "$line" "$right")
  fi
fi

printf "%b\n" "$line"
