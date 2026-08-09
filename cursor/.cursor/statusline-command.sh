#!/bin/sh
# =============================================================================
# Cursor CLI status line  —  fork of claude/.claude/statusline-command.sh
# =============================================================================
#     Auto  ctx:54%  CH80%  #2 ▁▂▃
#
# Declarative segments: model / context used % / cache-hit rate / message count /
# per-message context-growth bars (last ≤15). Narrow widths shed bars → messages
# → cache → model; ctx is retained. Cursor supplies render_width_chars, so no
# terminal probe or extra right margin is used. The configured Cursor padding
# remains separate.
#
# Cache hit rate uses the same formula as Claude:
#   cache_read / (input + cache_read + cache_creation), hidden at zero total.
# Model names of the form "Name (1M context)" compact to "Name [1M]" when present.
#
# No branch (dropped 2026-07-22), cost, fast/effort, or rate limits: Cursor's
# thinner payload does not provide those fields. This remains a fork, not a
# sourced library, so its divergence is explicit in the segment lists.
#
# DIAGNOSTICS: `bash statusline-command.sh --status [< payload.json]` uses piped
# stdin or the last reduced replay payload, prints fields/widths/shedding, and
# does not mutate replay or growth history.
#
# WIRING: cursor/setup-statusline.sh injects an absolute command path and
# "padding": 2 into machine-local ~/.cursor/cli-config.json. Cursor does not
# expand $HOME and reads statusLine only at session start.
#
# STATE: private per-session growth history and an atomically replaced reduced
# replay payload under ${XDG_CACHE_HOME:-$HOME/.cache}/cursor-statusline.
# =============================================================================

umask 077
DIAG=0; [ "${1:-}" = "--status" ] && DIAG=1
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cursor-statusline"
REPLAY="$STATE_DIR/last-payload.json"; [ "$DIAG" -eq 0 ] && mkdir -p "$STATE_DIR"
if [ "$DIAG" -eq 1 ] && [ -t 0 ]; then input=$(cat "$REPLAY" 2>/dev/null || printf '{}'); else input=$(cat); fi
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || input='{}'
if [ "$DIAG" -eq 0 ]; then
  tmp=$(mktemp "$STATE_DIR/last-payload.XXXXXX")
  if printf '%s' "$input" | jq '{session_id,model:{display_name:.model.display_name},render_width_chars,context_window:{used_percentage:.context_window.used_percentage,current_usage:{input_tokens:.context_window.current_usage.input_tokens,cache_read_input_tokens:.context_window.current_usage.cache_read_input_tokens,cache_creation_input_tokens:.context_window.current_usage.cache_creation_input_tokens}}}' >"$tmp"; then mv "$tmp" "$REPLAY"; else rm -f "$tmp"; fi
fi

model="" used="" session_id="" render_width=0 input_tokens=0 cache_read=0 cache_create=0
eval "$(printf '%s' "$input" | jq -r '
 @sh "model=\(.model.display_name // "")",
 @sh "used=\(.context_window.used_percentage // "")",
 @sh "session_id=\(.session_id // "")",
 @sh "render_width=\(.render_width_chars // 0)",
 @sh "input_tokens=\(.context_window.current_usage.input_tokens // 0)",
 @sh "cache_read=\(.context_window.current_usage.cache_read_input_tokens // 0)",
 @sh "cache_create=\(.context_window.current_usage.cache_creation_input_tokens // 0)"
')"
case "$render_width" in ''|*[!0-9]*)render_width=0;; esac
current_input=$((input_tokens+cache_read+cache_create))

HISTORY_FILE="$STATE_DIR/growth-${session_id}"; msg_count="" bars="" bar_count=0
if [ "$DIAG" -eq 0 ]; then
  # Direct glob avoids GNU-only find options (-mmin and -maxdepth), keeping
  # stale-history pruning portable to macOS's BSD find.
  find "$STATE_DIR"/growth-* -type f -mtime +7 -delete 2>/dev/null
  if [ -n "$session_id" ] && [ "$current_input" -gt 0 ] 2>/dev/null; then last=$(tail -1 "$HISTORY_FILE" 2>/dev/null || printf ''); [ "$last" = "$current_input" ] || printf '%s\n' "$current_input" >>"$HISTORY_FILE"; fi
fi
if [ -n "$session_id" ] && [ -f "$HISTORY_FILE" ]; then
  msg_count=$(wc -l <"$HISTORY_FILE" | tr -d ' ')
  data=$(awk '{v[n++]=$1} END{if(n<2)exit;for(i=1;i<n;i++){d=v[i]-v[i-1];if(d<0)d=0;x[k++]=d}s=k>15?k-15:0;m=0;for(i=s;i<k;i++)if(x[i]>m)m=x[i];if(m==0)exit;split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █",b," ");o="";c=0;for(i=s;i<k;i++){l=int(x[i]/m*7)+1;if(l>8)l=8;if(l<1)l=1;o=o b[l];c++}printf "%d %s",c,o}' "$HISTORY_FILE")
  if [ -n "$data" ]; then bar_count=${data%% *}; bars=${data#* }; fi
fi

cyan='\033[0;36m'; dim='\033[2m'; yellow='\033[0;33m'; red='\033[0;31m'; reset='\033[0m'
add_seg(){ eval "seg_plain_$1=\$2"; eval "seg_$1=\$3"; eval "segw_$1=\$4"; eval "segsep_$1=\${5:-2}"; eval "segdrop_$1=0"; }
SEGS="model ctx cache msgs bars"; SHED="bars msgs cache model"
if [ -n "$model" ]; then
  case "$model" in *" ("*" context)") _size=${model##* (}; _size=${_size%% *}; model="${model% (*} [${_size}]";; esac
  add_seg model "$model" "$(printf "${cyan}%s${reset}" "$model")" "${#model}"
fi
if [ -n "$used" ]; then n=$(printf '%.0f' "$used"); [ "$n" -ge 90 ] && c=$red || { [ "$n" -ge 70 ] && c=$yellow || c=$dim; }; p="ctx:${n}%"; add_seg ctx "$p" "$(printf "ctx:${c}%s%%${reset}" "$n")" "${#p}"; fi
if [ "$current_input" -gt 0 ] 2>/dev/null; then
  cache_rate=$(( (cache_read*100 + current_input/2) / current_input )); [ "$cache_rate" -ge 80 ] && c=$dim || { [ "$cache_rate" -ge 50 ] && c=$yellow || c=$red; }
  p="CH${cache_rate}%"; add_seg cache "$p" "$(printf "${c}%s${reset}" "$p")" "${#p}"
fi
if [ -n "$msg_count" ] && [ "$msg_count" -gt 0 ] 2>/dev/null; then p="#${msg_count}"; add_seg msgs "$p" "$(printf "${dim}%s${reset}" "$p")" "${#p}"; fi
[ -n "$bars" ] && add_seg bars "$bars" "$(printf "${dim}%s${reset}" "$bars")" "$bar_count" 1

render(){ out=""; outw=0; count=0; for name in $SEGS; do eval "present=\${segw_$name+x}"; [ -n "$present" ] || continue; eval "drop=\$segdrop_$name"; [ "$drop" -eq 1 ] && continue; eval "text=\$seg_$name"; eval "w=\$segw_$name"; eval "sep=\$segsep_$name"; if [ "$count" -gt 0 ]; then out="${out}$(printf '%*s' "$sep" '')"; outw=$((outw+sep)); fi; out="${out}${text}"; outw=$((outw+w)); count=$((count+1)); done; }
dropped=""
while :; do
  render
  [ "$render_width" -eq 0 ] && break
  [ "$outw" -le "$render_width" ] && break
  victim=""
  for name in $SHED; do eval "present=\${segw_$name+x}"; eval "drop=\${segdrop_$name:-0}"; if [ -n "$present" ] && [ "$drop" -eq 0 ]; then victim=$name; break; fi; done
  [ -n "$victim" ] || break
  eval "segdrop_$victim=1"; dropped="${dropped}${dropped:+ }${victim}"
done
render

ESC=$(printf '\033'); vis_width(){ printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
if [ "$DIAG" -eq 1 ]; then
  field(){ [ -n "$2" ] && printf 'field %-45s %s\n' "$1" "$2" || printf 'field %-45s EMPTY\n' "$1"; }
  field '.session_id' "$session_id"; field '.model.display_name' "$model"; field '.context_window.used_percentage' "$used"; field '.render_width_chars' "$render_width"; field '.context_window.current_usage.input_tokens' "$input_tokens"; field '.context_window.current_usage.cache_read_input_tokens' "$cache_read"; field '.context_window.current_usage.cache_creation_input_tokens' "$cache_create"
  printf 'config width=%s rmargin=0 (Cursor padding is external)\n' "$render_width"
  for name in $SEGS; do eval "present=\${segw_$name+x}"; [ -n "$present" ] || continue; eval "plain=\$seg_plain_$name"; eval "w=\$segw_$name"; eval "drop=\$segdrop_$name"; printf 'segment %-8s width=%-3s measured=%-3s dropped=%s text=%s\n' "$name" "$w" "$(vis_width "$plain")" "$drop" "$plain"; done
  printf 'shed %s\nresult width=%s text=%s\n' "${dropped:-none}" "$outw" "$out"; exit 0
fi
printf '%s\n' "$out"
