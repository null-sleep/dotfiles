#!/bin/bash
# One-time setup: load the theme-follow LaunchAgent so Claude Code and Neovim
# auto-follow the macOS appearance (see README → "Auto-follow on macOS appearance
# changes"). Run after `stow macos`, which symlinks the plist into
# ~/Library/LaunchAgents/.
#
# What it does: bootstraps (loads) com.dhruv.theme-follow into your GUI session
# and kickstarts it. The agent runs `theme watch`, a loop that applies `theme
# follow` on every macOS dark/light flip. Idempotent — re-run any time (e.g.
# after editing the plist) to reload cleanly.

set -euo pipefail

LABEL="com.dhruv.theme-follow"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ ! -e "$PLIST" ]; then
  echo "Error: $PLIST not found."
  echo "Run 'stow macos' from the repo root first, then re-run this script."
  exit 1
fi

# `theme` must be on disk where the agent expects it (~/.local/bin, stowed by the
# zsh package). Warn but don't abort — you might be setting up out of order.
if [ ! -e "$HOME/.local/bin/theme" ]; then
  echo "Warning: ~/.local/bin/theme not found — run 'stow zsh' so the watcher has"
  echo "         something to execute. Continuing to load the agent anyway."
fi

# Reload cleanly: bootout an existing instance (ignore 'not loaded'), then
# bootstrap fresh. bootout+bootstrap is the modern replacement for load/-w, and
# RunAtLoad in the plist starts the agent — no kickstart needed. bootout is
# asynchronous, so a back-to-back bootstrap of the same label can momentarily
# fail with EBUSY/EIO; retry a few times so re-running stays idempotent.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
for attempt in 1 2 3 4 5; do
  launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null && break
  if [ "$attempt" = 5 ]; then
    echo "Error: launchctl bootstrap failed after 5 attempts." >&2
    echo "Wait a moment and retry: launchctl bootstrap $DOMAIN \"$PLIST\"" >&2
    exit 1
  fi
  sleep 1
done

echo "Loaded $LABEL."
echo "Claude + nvim will now follow macOS appearance changes automatically."
echo
echo "Tip: enable System Settings → Appearance → Auto for sunset/sunrise switching."
echo "Check status with:  theme status     (logs: /tmp/theme-follow.{out,err}.log)"
echo "Disable with:       launchctl bootout $DOMAIN/$LABEL"
