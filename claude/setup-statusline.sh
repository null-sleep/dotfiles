#!/bin/bash
# One-time setup: inject statusLine block into ~/.claude/settings.json
# Run after `stow claude` to complete the status line setup.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
SCRIPT_CMD='bash $HOME/.claude/statusline-command.sh'

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if [ ! -f "$SETTINGS" ]; then
  echo "No settings.json found at $SETTINGS — creating minimal one"
  echo '{}' > "$SETTINGS"
fi

# settings.json is stowed (a symlink into the repo): write through the link.
# `mv tmp` onto the link path would replace the LINK with a plain file,
# silently de-adopting the stowed copy.
SETTINGS="$(readlink -f "$SETTINGS")"

# Check if statusLine already exists
if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
  # // empty: without it a statusLine object missing .command prints the
  # literal string "null" and the repair below never fires.
  current=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if echo "$current" | grep -q '/Users/'; then
    echo "Updating hardcoded path in statusLine.command to use \$HOME..."
    jq --arg cmd "$SCRIPT_CMD" '.statusLine.command = $cmd' "$SETTINGS" > "${SETTINGS}.tmp" \
      && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "Done."
  else
    echo "statusLine already configured: ${current:-<none>}"
  fi
else
  echo "Adding statusLine block to $SETTINGS..."
  jq --arg cmd "$SCRIPT_CMD" '. + {"statusLine": {"type": "command", "command": $cmd}}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Done."
fi
