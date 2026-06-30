#!/bin/bash
# One-time setup: point ~/.claude/settings.json at the "active" theme slot used
# by the unified `theme` switcher (see README → "Unified theme switching").
# Run after `stow claude`.
#
# Indirection: settings.json pins a FIXED slug, "custom:active", and the
# `theme dark|light` command swaps what ~/.claude/themes/active.json *contains*.
# Claude hot-reloads theme files, so this gives a live dark/light switch with no
# restart. This script just sets the preference and seeds active.json from a
# sensible default; settings.json itself is not stowed (machine-specific).

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
THEME="custom:active"
THEMES_DIR="$HOME/.claude/themes"
DEFAULT_FILE="$THEMES_DIR/catppuccin-latte.json"   # seed for active.json
ACTIVE_FILE="$THEMES_DIR/active.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

# Don't point settings.json at a theme that isn't stowed yet — run `stow claude` first.
if [ ! -e "$DEFAULT_FILE" ]; then
  echo "Error: default theme file not found at $DEFAULT_FILE"
  echo "Run 'stow claude' from the repo root first, then re-run this script."
  exit 1
fi

# Seed active.json (a real file, not stowed) so "custom:active" resolves. Don't
# clobber an existing active.json — it holds whatever mode you last switched to.
# Atomic write (temp + mv): replaces a symlink instead of writing through it.
if [ ! -e "$ACTIVE_FILE" ]; then
  tmp="$(mktemp "$THEMES_DIR/.active.XXXXXX")"
  cp -fL "$DEFAULT_FILE" "$tmp" && mv -f "$tmp" "$ACTIVE_FILE"
  echo "Seeded $ACTIVE_FILE from $(basename "$DEFAULT_FILE")."
fi

if [ ! -f "$SETTINGS" ]; then
  echo "No settings.json found at $SETTINGS — creating minimal one"
  echo '{}' > "$SETTINGS"
fi

current=$(jq -r '.theme // empty' "$SETTINGS")

if [ "$current" = "$THEME" ]; then
  echo "Theme already set to $THEME — no change."
else
  [ -n "$current" ] && echo "Changing theme from '$current' to '$THEME'..." \
                    || echo "Setting theme to '$THEME'..."
  jq --arg t "$THEME" '.theme = $t' "$SETTINGS" > "${SETTINGS}.tmp" \
    && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Done. Use 'theme dark|light|toggle' to switch."
fi
