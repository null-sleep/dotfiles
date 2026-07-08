#!/bin/bash
# One-time setup: load the yknotify LaunchAgent so YubiKey touch prompts fire
# a notification (see README → "yknotify"). Run after `stow --no-folding
# yknotify`, which symlinks the plist into ~/Library/LaunchAgents/ and the
# watcher script into ~/.local/bin/.
#
# What it does: bootstraps (loads) com.dhruv.yknotify into your GUI session.
# Also boots out the legacy com.user.yknotify label from the package's old
# layout, if one is loaded. Idempotent — re-run any time (e.g. after editing
# the plist) to reload cleanly.

set -euo pipefail

LABEL="com.dhruv.yknotify"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ ! -e "$PLIST" ]; then
  echo "Error: $PLIST not found."
  echo "Run 'stow --no-folding yknotify' from the repo root first, then re-run this script."
  exit 1
fi

# The agent needs both binaries at runtime. Warn but don't abort — you might
# be setting up out of order; the watcher logs a clear error if they're still
# missing when it starts.
if ! command -v yknotify >/dev/null 2>&1 && [ ! -x "$HOME/go/bin/yknotify" ]; then
  echo "Warning: yknotify binary not found — run:"
  echo "         go install github.com/noperator/yknotify@latest"
fi
if ! command -v terminal-notifier >/dev/null 2>&1 \
    && [ ! -x /opt/homebrew/bin/terminal-notifier ] \
    && [ ! -x /usr/local/bin/terminal-notifier ]; then
  echo "Warning: terminal-notifier not found — run: brew install terminal-notifier"
fi

# Unload the legacy label from the pre-rework package layout (~/yknotify.sh +
# com.user.yknotify.plist). Harmless when it was never loaded.
launchctl bootout "$DOMAIN/com.user.yknotify" 2>/dev/null || true

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
echo "YubiKey OpenPGP touch prompts will now fire a notification."
echo
echo "Check status with:  launchctl print $DOMAIN/$LABEL   (logs: /tmp/yknotify.{out,err}.log)"
echo "Disable with:       launchctl bootout $DOMAIN/$LABEL"
