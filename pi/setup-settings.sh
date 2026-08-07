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
THEMES_DIR="$HOME/.pi/agent/themes"
ACTIVE_FILE="$THEMES_DIR/active.json"

# Fill-in-only defaults: set when missing, never overwritten. A model or
# thinking level you change later survives a re-run.
DEFAULTS='{
  "defaultProvider": "openrouter",
  "defaultModel": "anthropic/claude-sonnet-5",
  "defaultThinkingLevel": "medium",
  "quietStartup": true
}'

# `theme` is the exception — it is *forced*, not filled in. It names the fixed
# slot the `theme` switcher writes into (themes/active.json), the same
# indirection as Claude Code's "custom:active". Pointing it at a real theme name
# would break the switcher, so a stale value gets corrected rather than kept.
THEME_SLOT="active"

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
current_theme="$(jq -r '.theme // empty' "$SETTINGS")"
if [ -n "$current_theme" ] && [ "$current_theme" != "$THEME_SLOT" ]; then
  echo "Repointing theme from '$current_theme' to '$THEME_SLOT' (the switcher's slot)."
fi

jq --argjson defaults "$DEFAULTS" --arg slot "$THEME_SLOT" \
  '($defaults * .) | .theme = $slot' "$SETTINGS" >"${SETTINGS}.tmp" \
  && mv "${SETTINGS}.tmp" "$SETTINGS"

echo "Seeded pi defaults in $SETTINGS:"
jq -r 'to_entries[] | "  \(.key) = \(.value|tostring)"' "$SETTINGS"

# Seed themes/active.json so `"theme": "active"` resolves on first launch.
# Seeded from the CURRENT macOS appearance, not a fixed light default — setting
# up a machine that's already in dark mode would otherwise leave pi light until
# the next `theme` flip. Read via `defaults` (no Automation prompt), matching
# the reader in zsh/.local/bin/theme.
case "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" in
  [Dd]ark*) seed=dracula ;;
  *)        seed=catppuccin-latte ;;
esac
SEED_FILE="$THEMES_DIR/$seed.json"

if [ ! -e "$SEED_FILE" ]; then
  echo
  echo "Warning: $SEED_FILE not found — run 'stow --no-folding pi' from the repo"
  echo "root first, then re-run this script, or pi will fall back to its"
  echo "built-in theme because \"active\" resolves to nothing."
elif [ -e "$ACTIVE_FILE" ]; then
  echo "Theme: $ACTIVE_FILE already exists — left as-is."
else
  # Atomic write, and rewrite `name` to match the pinned slot. Same as the
  # `theme` script does on every switch.
  tmp="$(mktemp "$THEMES_DIR/.active.XXXXXX")"
  jq '.name = "active"' "$SEED_FILE" >"$tmp" && mv -f "$tmp" "$ACTIVE_FILE"
  echo "Theme: seeded $ACTIVE_FILE from $seed (current macOS appearance)."
fi

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`pi\`."
echo "Switch themes with \`theme dark|light|toggle\`."
