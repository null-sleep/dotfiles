#!/bin/bash
# Validate the statusLine block tracked in ~/.claude/settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$SCRIPT_DIR/.claude/settings.json"
SCRIPT_CMD='bash $HOME/.claude/statusline-command.sh'

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

"$SCRIPT_DIR/setup-settings.sh" --check

if ! jq -e --arg cmd "$SCRIPT_CMD" \
  '.statusLine == {"type": "command", "command": $cmd}' "$SETTINGS" >/dev/null; then
  echo "Error: tracked statusLine config is not canonical in $SETTINGS." >&2
  echo "Expected command: $SCRIPT_CMD" >&2
  exit 1
fi

echo "statusLine is configured in the tracked settings."
