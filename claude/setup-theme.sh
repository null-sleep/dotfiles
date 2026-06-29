#!/bin/bash
# One-time setup: activate the Catppuccin Latte theme in ~/.claude/settings.json
# Run after `stow claude` to point settings.json at the stowed theme file.
#
# The theme *file* (~/.claude/themes/catppuccin-latte.json) is symlinked via stow.
# This script only sets the `theme` preference, since settings.json is not stowed
# (it holds machine-specific content: plugins, hooks, MCP servers, permissions).

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
THEME="custom:catppuccin-latte"
THEME_FILE="$HOME/.claude/themes/catppuccin-latte.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

# Don't point settings.json at a theme that isn't stowed yet — run `stow claude` first.
if [ ! -e "$THEME_FILE" ]; then
  echo "Error: theme file not found at $THEME_FILE"
  echo "Run 'stow claude' from the repo root first, then re-run this script."
  exit 1
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
  echo "Done."
fi
