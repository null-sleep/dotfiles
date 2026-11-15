# Zed-only Claude `Stop` bell

Status: not started (2026-11-15). Follow-up to the global
`preferredNotifChannel: "terminal_bell"` setting in
`claude/.claude/settings.json`.

## Target

The omp ACP integration's notifications are the ideal: instant, and Zed
knows when the agent finished or is waiting. I like how they work. A Claude
Terminal Thread should feel as close to that as a bell allows; a bell can't
distinguish "finished" from "needs permission", but timing should match.

## Why

Zed Terminal Threads turn a terminal bell into the same pop-up and sound as an
ACP thread finishing ([docs](https://zed.dev/docs/ai/terminal-threads)). The
global `terminal_bell` setting is the cheap way to get that, but it has costs:

- **Slow.** Claude sends the finish bell about 60 seconds after it stops, and
  only if you haven't typed since. The permission bell comes after about 6
  seconds. The ACP pop-up is instant.
- **Global.** It replaces Claude's default `auto` channel, which sends a real
  desktop notification in Ghostty, with a bell (Ghostty default
  `bell-features`: Dock bounce + 🔔 tab title, no sound, no border).

## Idea

Replace the global setting with hooks that ring the bell only inside Zed and
immediately:

- `Stop` hook (turn finished) and `Notification` hook (permission / input
  needed), each doing roughly
  `[ "$TERM_PROGRAM" = zed ] && printf '\a' > /dev/tty`.
- Remove `preferredNotifChannel` (back to `auto`) so Ghostty keeps its desktop
  notifications.
- Existing `sidekick-notify.sh` hooks are separate and exit early outside a
  sidekick-managed nvim, so they don't conflict. Add the new commands as
  separate registrations next to them.

## Unverified — check first

- Zed sets `TERM_PROGRAM=zed` in Terminal Threads (believed, not checked).
  Print `$TERM_PROGRAM` in a thread.
- Hook subprocesses can open `/dev/tty`. If not, find another way to reach the
  terminal (for example walking up to the parent's tty).
- A bell written from a hook reaches Zed as a bell while the thread is
  unfocused.
- Whether herdr or tmux between Zed and Claude swallows the bell (tmux needs
  `set -g allow-passthrough on`; herdr unknown).

## If it works

- Edit `claude/.claude/settings.json`: add the hooks, drop
  `preferredNotifChannel`.
- Extend `claude/tests/settings-invariants.sh` (hook counts) and update the
  README → Claude Code → What's managed note about the bell.
- Prune this file.
