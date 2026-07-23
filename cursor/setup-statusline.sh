#!/bin/bash
# One-time setup: inject the statusLine block into ~/.cursor/cli-config.json.
# Run after `stow --no-folding cursor` to complete the status line setup.
# cli-config.json is machine-local (auth, model prefs) and NOT stowed — this
# merges only the statusLine key into it, preserving everything else.
# Full reference (payload schema, wiring, what's rendered) lives in the header
# of cursor/.cursor/statusline-command.sh.

set -euo pipefail

CONFIG="$HOME/.cursor/cli-config.json"
# Unlike Claude Code, Cursor's statusLine runner does NOT shell-expand $HOME in
# the command string — a literal "$HOME/..." never resolves and the line renders
# blank. So expand it here (double quotes) and inject the concrete path. That's
# safe because cli-config.json is machine-local and not stowed, and setup re-runs
# per machine, so each writes its own $HOME.
SCRIPT_CMD="bash $HOME/.cursor/statusline-command.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "No cli-config.json found at $CONFIG — creating minimal one"
  echo '{}' > "$CONFIG"
fi

# // empty: without it a statusLine object missing .command yields the literal
# string "null" and the checks below misfire.
current=$(jq -r '.statusLine.command // empty' "$CONFIG")
if [ "$current" = "$SCRIPT_CMD" ]; then
  echo "statusLine already configured: $current"
elif echo "$current" | grep -q 'statusline-command\.sh'; then
  # Points at our script but with a stale path (e.g. an old literal $HOME, or a
  # different machine's home) — repair it to this machine's absolute path.
  echo "Repairing statusLine.command → $SCRIPT_CMD"
  jq --arg cmd "$SCRIPT_CMD" '.statusLine.command = $cmd' "$CONFIG" > "${CONFIG}.tmp" \
    && mv "${CONFIG}.tmp" "$CONFIG"
  echo "Done."
else
  echo "Adding statusLine block to $CONFIG..."
  # padding: 2 is Cursor's convention for the statusLine block (Claude uses 0).
  jq --arg cmd "$SCRIPT_CMD" '. + {"statusLine": {"type": "command", "command": $cmd, "padding": 2}}' \
    "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
  echo "Done."
fi
