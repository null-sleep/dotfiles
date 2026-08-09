#!/bin/sh
# =============================================================================
# Claude Code status line  —  https://code.claude.com/docs/en/statusline
# =============================================================================
# Usage: Opus 4.8 [1M]  hi  ctx:22%  CH87%  #109 ▁▂▃    5h:10%/3h34m  7d:1%
#
# Declarative segments are rendered as a left cluster and a right-aligned
# usage/cost cluster. Narrow terminals shed whole segments in this order:
# bars → 7d → flag → messages → cache → 5h/cost → model; ctx is retained.
# Unknown width keeps the compact two-space join and sheds nothing.
#
# Segments: .model.display_name / ⚡+.effort.level / context used % / cache-hit
# rate / message count / context-growth bars / 5h and 7d limits (usage mode), or
# session/message/month cost (CLAUDE_STATUSLINE_MODE=cost). Cache hit rate is
# cache_read / (input + cache_read + cache_creation), hidden only at zero total.
# Branch is intentionally absent (decision 2026-07-22).
#
# WIDTH: Claude exports COLUMNS. RMARGIN reserves three columns before Claude's
# own ellipsis boundary. Widths are stored with each segment: ASCII widths use
# shell character counts, sparkline width comes from awk, and ⚡ declares its
# two terminal cells explicitly. The renderer never measures ANSI text.
#
# DIAGNOSTICS: `bash statusline-command.sh --status [< payload.json]` uses stdin
# when piped, otherwise the last reduced payload in STATE_DIR. It prints field
# resolution, segment declared/measured widths, and the current shed decision;
# it does not mutate histories, cost logs, or replay state.
#
# WIRING: ~/.claude/settings.json runs
#   bash $HOME/.claude/statusline-command.sh
# via claude/setup-statusline.sh. Sibling fork: cursor/.cursor/statusline-command.sh.
#
# STATE: ${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline contains private,
# per-session growth/cost scratch plus an atomically replaced reduced replay
# payload. Scratch older than 7d is pruned. Monthly API cost lives separately
# in ~/.claude/cost-log.
# =============================================================================

umask 077
DIAG=0
[ "${1:-}" = "--status" ] && DIAG=1
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
REPLAY="$STATE_DIR/last-payload.json"
[ "$DIAG" -eq 0 ] && mkdir -p "$STATE_DIR"

if [ "$DIAG" -eq 1 ] && [ -t 0 ]; then
  input=$(cat "$REPLAY" 2>/dev/null || printf '{}')
else
  input=$(cat)
fi
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || input='{}'

# Keep replay data limited to fields this script diagnoses; never cache paths or
# transcript metadata. Diagnostic runs are read-only.
if [ "$DIAG" -eq 0 ]; then
  replay_tmp=$(mktemp "$STATE_DIR/last-payload.XXXXXX")
  if printf '%s' "$input" | jq '{session_id,model:{display_name:.model.display_name},context_window:{used_percentage:.context_window.used_percentage,current_usage:{input_tokens:.context_window.current_usage.input_tokens,cache_read_input_tokens:.context_window.current_usage.cache_read_input_tokens,cache_creation_input_tokens:.context_window.current_usage.cache_creation_input_tokens}},fast_mode,effort:{level:.effort.level},cost:{total_cost_usd:.cost.total_cost_usd},rate_limits:{five_hour:{used_percentage:.rate_limits.five_hour.used_percentage,resets_at:.rate_limits.five_hour.resets_at},seven_day:{used_percentage:.rate_limits.seven_day.used_percentage}}}' >"$replay_tmp"; then
    mv "$replay_tmp" "$REPLAY"
  else
    rm -f "$replay_tmp"
  fi
fi

model="" used="" fast="false" effort="" session_id="" cost=""
rl_5h="" rl_5h_resets="" rl_7d="" input_tokens=0 cache_read=0 cache_create=0
# One JSON parse supplies every render field.
eval "$(printf '%s' "$input" | jq -r '
  @sh "model=\(.model.display_name // "")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "fast=\(.fast_mode // false)",
  @sh "effort=\(.effort.level // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "cost=\(.cost.total_cost_usd // "")",
  @sh "rl_5h=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "rl_5h_resets=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl_7d=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "input_tokens=\(.context_window.current_usage.input_tokens // 0)",
  @sh "cache_read=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "cache_create=\(.context_window.current_usage.cache_creation_input_tokens // 0)"
')"
current_input=$((input_tokens + cache_read + cache_create))

# --- Stateful values (diagnostics may read, never write) ---
msg_count="" bars="" bar_count=0 last_msg_cost="" monthly_cost=""
HISTORY_FILE="$STATE_DIR/growth-${session_id}"
if [ "$DIAG" -eq 0 ]; then
  # Run this small direct-file sweep per render: BSD find lacks GNU's -mmin
  # and -maxdepth options, and these are the only scratch-file patterns here.
  find "$STATE_DIR"/growth-* "$STATE_DIR"/prevcost-* -type f -mtime +7 -delete 2>/dev/null
  if [ -n "$session_id" ] && [ "$current_input" -gt 0 ] 2>/dev/null; then
    last_val=$(tail -1 "$HISTORY_FILE" 2>/dev/null || printf '')
    [ "$last_val" = "$current_input" ] || printf '%s\n' "$current_input" >>"$HISTORY_FILE"
  fi
fi
if [ -n "$session_id" ] && [ -f "$HISTORY_FILE" ]; then
  msg_count=$(wc -l <"$HISTORY_FILE" | tr -d ' ')
  bars_data=$(awk '
    { v[n++]=$1 }
    END {
      if (n<2) exit
      for(i=1;i<n;i++){ d=v[i]-v[i-1]; if(d<0)d=0; delta[nd++]=d }
      start=nd>15?nd-15:0; max=0
      for(i=start;i<nd;i++)if(delta[i]>max)max=delta[i]
      if(max==0)exit
      split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █",b," "); out=""; count=0
      for(i=start;i<nd;i++){ level=int(delta[i]/max*7)+1; if(level>8)level=8; if(level<1)level=1; out=out b[level]; count++ }
      printf "%d %s",count,out
    }' "$HISTORY_FILE")
  if [ -n "$bars_data" ]; then bar_count=${bars_data%% *}; bars=${bars_data#* }; fi
fi

if [ "$CLAUDE_STATUSLINE_MODE" = "cost" ]; then
  if [ -n "$session_id" ] && [ -n "$cost" ] && [ "$cost" != 0 ]; then
    PREV_COST_FILE="$STATE_DIR/prevcost-${session_id}"
    prev_cost=$(cat "$PREV_COST_FILE" 2>/dev/null || printf 0)
    last_msg_cost=$(awk -v c="$cost" -v p="$prev_cost" 'BEGIN{printf "%.2f",c-p}')
    if [ "$DIAG" -eq 0 ]; then
      printf '%s\n' "$cost" >"$PREV_COST_FILE"
      COST_DIR="$HOME/.claude/cost-log"; mkdir -p "$COST_DIR"
      MONTH_FILE="$COST_DIR/$(date +%Y-%m).tsv"
      if [ -f "$MONTH_FILE" ] && grep -q "^${session_id}$(printf '\t')" "$MONTH_FILE" 2>/dev/null; then
        month_tmp=$(mktemp "${MONTH_FILE}.XXXXXX")
        awk -v sid="$session_id" -v c="$cost" -F '\t' 'BEGIN{OFS="\t"}$1==sid{$2=c}{print}' "$MONTH_FILE" >"$month_tmp" && mv "$month_tmp" "$MONTH_FILE"
      else
        printf '%s\t%s\n' "$session_id" "$cost" >>"$MONTH_FILE"
      fi
    else
      MONTH_FILE="$HOME/.claude/cost-log/$(date +%Y-%m).tsv"
    fi
    [ -f "$MONTH_FILE" ] && monthly_cost=$(awk -F '\t' '{s+=$2}END{printf "%.2f",s}' "$MONTH_FILE")
  fi
fi

resets_in=""
if [ "$CLAUDE_STATUSLINE_MODE" != "cost" ] && [ -n "$rl_5h_resets" ] && [ "$rl_5h_resets" != 0 ]; then
  now=$(date +%s); diff=$((rl_5h_resets-now))
  [ "$diff" -gt 0 ] && resets_in=$(printf '%dh%02dm' "$((diff/3600))" "$(((diff%3600)/60))")
fi

cyan='\033[0;36m'; dim='\033[2m'; yellow='\033[0;33m'; red='\033[0;31m'; reset='\033[0m'
pick_color() { [ "$1" -ge "$2" ] && printf '%s' "$red" || { [ "$1" -ge "$3" ] && printf '%s' "$yellow" || printf '%s' "$dim"; }; }
# add_seg NAME CLUSTER PLAIN COLORED WIDTH [separator-before]
add_seg() {
  eval "seg_plain_$1=\$3"; eval "seg_$1=\$4"; eval "segw_$1=\$5"
  eval "segsep_$1=\${6:-2}"; eval "segcluster_$1=\$2"; eval "segdrop_$1=0"
}
LEFT="model flag ctx cache msgs bars"; RIGHT=""

if [ -n "$model" ]; then
  case "$model" in *" ("*" context)") _size=${model##* (}; _size=${_size%% *}; model="${model% (*} [${_size}]";; esac
  add_seg model L "$model" "$(printf "${cyan}%s${reset}" "$model")" "${#model}"
fi
flag_plain=""; flag=""; flag_width=0
if [ "$fast" = true ]; then flag_plain="⚡"; flag=$(printf "${yellow}⚡${reset}"); flag_width=2; fi
if [ -n "$effort" ]; then
  case "$effort" in low)eff=lo;; medium)eff=med;; high)eff=hi;; xhigh)eff=xhi;; max)eff=max;; ultracode)eff=uc;; *)eff=$effort;; esac
  flag_plain="${flag_plain}${eff}"; flag="${flag}$(printf "${dim}%s${reset}" "$eff")"; flag_width=$((flag_width+${#eff}))
fi
[ -n "$flag_plain" ] && add_seg flag L "$flag_plain" "$flag" "$flag_width"
if [ -n "$used" ]; then used_int=$(printf '%.0f' "$used"); c=$(pick_color "$used_int" 90 70); p="ctx:${used_int}%"; add_seg ctx L "$p" "$(printf "ctx:${c}%s%%${reset}" "$used_int")" "${#p}"; fi
cache_total=$current_input
if [ "$cache_total" -gt 0 ] 2>/dev/null; then
  cache_rate=$(( (cache_read*100 + cache_total/2) / cache_total )); [ "$cache_rate" -ge 80 ] && c=$dim || { [ "$cache_rate" -ge 50 ] && c=$yellow || c=$red; }
  p="CH${cache_rate}%"; add_seg cache L "$p" "$(printf "${c}%s${reset}" "$p")" "${#p}"
fi
if [ -n "$msg_count" ] && [ "$msg_count" -gt 0 ] 2>/dev/null; then p="#${msg_count}"; add_seg msgs L "$p" "$(printf "${dim}%s${reset}" "$p")" "${#p}"; fi
[ -n "$bars" ] && add_seg bars L "$bars" "$(printf "${dim}%s${reset}" "$bars")" "$bar_count" 1

if [ "$CLAUDE_STATUSLINE_MODE" = cost ]; then
  RIGHT="cost"
  if [ -n "$cost" ] && [ "$cost" != 0 ]; then
    p=$(printf '$%.2f' "$cost"); extra=""; [ -n "$last_msg_cost" ] && [ "$last_msg_cost" != 0.00 ] && extra=" +\$${last_msg_cost}"; p="${p}${extra}"
    [ -n "$monthly_cost" ] && p="${p} (mo:\$${monthly_cost})"
    add_seg cost R "$p" "$(printf "${dim}%s${reset}" "$p")" "${#p}"
  fi
  SHED="bars flag msgs cache cost model"
else
  RIGHT="limit5 limit7"
  if [ -n "$rl_5h" ]; then n=$(printf '%.0f' "$rl_5h"); c=$(pick_color "$n" 80 50); p="5h:${n}%"; colored=$(printf "5h:${c}%s%%${reset}" "$n"); if [ -n "$resets_in" ]; then p="${p}/${resets_in}"; colored="${colored}$(printf "${dim}/%s${reset}" "$resets_in")"; fi; add_seg limit5 R "$p" "$colored" "${#p}"; fi
  if [ -n "$rl_7d" ]; then n=$(printf '%.0f' "$rl_7d"); c=$(pick_color "$n" 80 50); p="7d:${n}%"; add_seg limit7 R "$p" "$(printf "7d:${c}%s%%${reset}" "$n")" "${#p}"; fi
  SHED="bars limit7 flag msgs cache limit5 model"
fi

# Render a cluster and publish rendered text, width, and count in globals.
render_cluster() {
  rc_text=""; rc_width=0; rc_count=0
  for name in $1; do
    eval "present=\${segw_$name+x}"; [ -n "$present" ] || continue
    eval "drop=\$segdrop_$name"; [ "$drop" -eq 1 ] && continue
    eval "text=\$seg_$name"; eval "w=\$segw_$name"; eval "sep=\$segsep_$name"
    if [ "$rc_count" -gt 0 ]; then rc_text="${rc_text}$(printf '%*s' "$sep" '')"; rc_width=$((rc_width+sep)); fi
    rc_text="${rc_text}${text}"; rc_width=$((rc_width+w)); rc_count=$((rc_count+1))
  done
}
COLS="${COLUMNS:-0}"; case "$COLS" in ''|*[!0-9]*)COLS=0;; esac; RMARGIN=3; dropped=""
fit_segments() {
  while :; do
    render_cluster "$LEFT"; lw=$rc_width; lc=$rc_count
    render_cluster "$RIGHT"; rw=$rc_width; rc=$rc_count
    between=0; [ "$lc" -gt 0 ] && [ "$rc" -gt 0 ] && between=2
    total=$((lw+rw+between))
    [ "$COLS" -eq 0 ] && break
    [ "$total" -le $((COLS-RMARGIN)) ] && break
    victim=""
    for name in $SHED; do eval "present=\${segw_$name+x}"; eval "drop=\${segdrop_$name:-0}"; if [ -n "$present" ] && [ "$drop" -eq 0 ]; then victim=$name; break; fi; done
    [ -n "$victim" ] || break
    eval "segdrop_$victim=1"; dropped="${dropped}${dropped:+ }${victim}"
  done
}
fit_segments
render_cluster "$LEFT"; line=$rc_text; lw=$rc_width; lc=$rc_count
render_cluster "$RIGHT"; right=$rc_text; rw=$rc_width; rc=$rc_count
if [ "$lc" -gt 0 ] && [ "$rc" -gt 0 ]; then
  if [ "$COLS" -gt 0 ]; then gap=$((COLS-lw-rw-RMARGIN)); [ "$gap" -lt 2 ] && gap=2; else gap=2; fi
  line="${line}$(printf '%*s' "$gap" '')${right}"
elif [ "$rc" -gt 0 ]; then
  if [ "$COLS" -gt 0 ]; then gap=$((COLS-rw-RMARGIN)); [ "$gap" -lt 0 ] && gap=0; line="$(printf '%*s' "$gap" '')${right}"; else line=$right; fi
fi

ESC=$(printf '\033')
vis_width() { printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
if [ "$DIAG" -eq 1 ]; then
  field() { [ -n "$2" ] && printf 'field %-38s %s\n' "$1" "$2" || printf 'field %-38s EMPTY\n' "$1"; }
  field '.session_id' "$session_id"; field '.model.display_name' "$model"; field '.context_window.used_percentage' "$used"
  field '.context_window.current_usage.input_tokens' "$input_tokens"; field '.context_window.current_usage.cache_read_input_tokens' "$cache_read"; field '.context_window.current_usage.cache_creation_input_tokens' "$cache_create"
  field '.fast_mode' "$fast"; field '.effort.level' "$effort"; field '.cost.total_cost_usd' "$cost"; field '.rate_limits.five_hour.used_percentage' "$rl_5h"; field '.rate_limits.five_hour.resets_at' "$rl_5h_resets"; field '.rate_limits.seven_day.used_percentage' "$rl_7d"
  printf 'config mode=%s width=%s rmargin=%s\n' "${CLAUDE_STATUSLINE_MODE:-usage}" "$COLS" "$RMARGIN"
  for name in $LEFT $RIGHT; do eval "present=\${segw_$name+x}"; [ -n "$present" ] || continue; eval "plain=\$seg_plain_$name"; eval "w=\$segw_$name"; eval "drop=\$segdrop_$name"; printf 'segment %-8s width=%-3s measured=%-3s dropped=%s text=%s\n' "$name" "$w" "$(vis_width "$plain")" "$drop" "$plain"; done
  printf 'shed %s\n' "${dropped:-none}"; printf 'result width=%s text=%s\n' "$((lw+rw+$( [ "$lc" -gt 0 ] && [ "$rc" -gt 0 ] && printf %s "${gap:-2}" || { [ "$rc" -gt 0 ] && [ "$COLS" -gt 0 ] && printf %s "${gap:-0}" || printf 0; } )))" "$line"
  exit 0
fi
printf '%s\n' "$line"
