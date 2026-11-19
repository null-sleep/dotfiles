#!/bin/bash
# Claude Code hook -> instant terminal bell when a turn ends or Claude needs
# you (plans/zed-claude-stop-bell.md). Registered on Stop, StopFailure,
# PermissionRequest and Elicitation. Per terminal ($TERM_PROGRAM):
#   ghostty  bare BEL -> Dock bounce + 🔔 tab title (Claude's own `auto`
#            desktop banner still follows on its usual delay).
#   zed      caption title + BEL -> Terminal Thread pop-up (below).
#   other    nothing.
#
# Zed's terminal pop-up has no caption line; it shows the terminal title read
# at bell time. So set the title to "<glyph> <why> · <session title>", then
# ring. A thread renamed in Zed shows its own name instead, but Zed keeps a
# leading symbol + space from the terminal title, so the glyph still shows.
# Claude rewrites its own title soon after.
#
# Hooks have no controlling tty, so both go out via `terminalSequence`:
# Claude writes it to its own terminal. Claude ignores it under -p and the SDK,
# so nested runs and Claude over ACP stay silent.
#
# Always exit 0: exit 2 would decline an Elicitation or block a Stop.
# Shells nested in Zed (herdr, nvim's terminal) inherit TERM_PROGRAM; that's fine.
# tmux overwrites TERM_PROGRAM, so the hook stays silent inside it.

bell='{"terminalSequence":"\u0007"}'
case ${TERM_PROGRAM:-} in
  ghostty) printf '%s\n' "$bell"; exit 0 ;;
  zed) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || { printf '%s\n' "$bell"; exit 0; }

if command -v timeout >/dev/null 2>&1; then input=$(timeout 2 cat 2>/dev/null)
else input=$(cat 2>/dev/null); fi

caption=$(jq -r '
  def short: tostring | if length > 40 then .[:39] + "…" else . end;
  if .hook_event_name == "Stop" then "✓ Finished"
  elif .hook_event_name == "StopFailure" then
    "✗ Error" + (if (.error // "") != "" then ": " + (.error | short) else "" end)
  elif .hook_event_name == "PermissionRequest" then
    if .tool_name == "AskUserQuestion" then "? Question for you"
    elif .tool_name == "ExitPlanMode" then "☰ Plan ready for review"
    else "⚠ Needs permission: " + ((.tool_name // "tool") | sub("^mcp__"; "") | short)
    end
  elif .hook_event_name == "Elicitation" then
    "? Input requested" + (if (.mcp_server_name // "") != "" then ": " + (.mcp_server_name | short) else "" end)
  else empty end
' <<<"$input" 2>/dev/null)
[ -n "$caption" ] || { printf '%s\n' "$bell"; exit 0; }

# Session title: a /rename (customTitle) wins over Claude's generated aiTitle.
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
topic=
if [ -f "$transcript" ]; then
  # Last record of each type, decoded by jq so escaped quotes/unicode survive.
  topic=$(grep -F '"type":"custom-title"' "$transcript" 2>/dev/null | tail -1 |
    jq -r '.customTitle // empty' 2>/dev/null)
  [ -n "$topic" ] ||
    topic=$(grep -F '"type":"ai-title"' "$transcript" 2>/dev/null | tail -1 |
      jq -r '.aiTitle // empty' 2>/dev/null)
fi

# OSC 2 (set title) terminated by BEL, then the bell itself.
jq -n -c --arg caption "$caption" --arg topic "$topic" \
  '{terminalSequence: ("\u001b]2;" + $caption
    + (if $topic != "" then " · " + $topic else "" end) + "\u0007\u0007")}' 2>/dev/null ||
  printf '%s\n' "$bell"
exit 0
