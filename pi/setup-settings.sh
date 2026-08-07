#!/bin/bash
# One-time setup: seed this machine's ~/.pi/agent/settings.json with the
# repo's pi defaults — OpenRouter as the provider, the default model and
# thinking level, and the starting theme.
#
# settings.json is deliberately NOT stowed. pi *writes* to it: it stamps
# `lastChangelogVersion` after an update, `/settings` edits land there, and the
# `theme` script rewrites the `theme` key on every light/dark switch. A stowed
# symlink would send all of that straight into this repo, so the file stays
# machine-local and this script merges only the keys we care about — the same
# split as ~/.claude/settings.json and ~/.cursor/cli-config.json.
#
# Idempotent: re-running when already configured is a no-op. It only sets keys
# that are missing, so a model or theme you later change by hand (or via the
# `theme` script) is preserved rather than reset.
#
# Usage:
#   bash ~/src/dotfiles/pi/setup-settings.sh

set -euo pipefail

SETTINGS="$HOME/.pi/agent/settings.json"

# The keys this repo seeds. Anything already present in settings.json wins.
DEFAULTS='{
  "defaultProvider": "openrouter",
  "defaultModel": "anthropic/claude-sonnet-5",
  "defaultThinkingLevel": "medium",
  "quietStartup": true,
  "theme": "light"
}'

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v pi >/dev/null 2>&1; then
  echo "Warning: pi is not on PATH — install it first:"
  echo "  npm install -g --ignore-scripts @earendil-works/pi-coding-agent"
  echo "Continuing anyway; the settings file is written either way."
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"

# `$defaults * .` — existing values override the defaults, so this fills in
# only what's missing. Write to a temp file and mv so a crash mid-write can't
# truncate a working settings file.
jq --argjson defaults "$DEFAULTS" '$defaults * .' "$SETTINGS" >"${SETTINGS}.tmp" \
  && mv "${SETTINGS}.tmp" "$SETTINGS"

echo "Seeded pi defaults in $SETTINGS:"
jq -r 'to_entries[] | "  \(.key) = \(.value|tostring)"' "$SETTINGS"

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`pi\`."
