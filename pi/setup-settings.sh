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
# The switcher itself, from the repo — resolved relative to this script so it
# works before `stow zsh` has put `theme` on PATH.
THEME_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/zsh/.local/bin/theme"

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

tmp="$(mktemp "${SETTINGS}.XXXXXX")"
jq --argjson defaults "$DEFAULTS" --arg slot "$THEME_SLOT" \
  '($defaults * .) | .theme = $slot' "$SETTINGS" >"$tmp" \
  && mv "$tmp" "$SETTINGS" || { rm -f "$tmp"; exit 1; }

echo "Seeded pi defaults in $SETTINGS:"
jq -r 'to_entries[] | "  \(.key) = \(.value|tostring)"' "$SETTINGS"

# Seed themes/active.json so `"theme": "active"` resolves on first launch.
# `theme seed` owns the palette choice — the pair lives only in that script's
# LIGHT/DARK arrays — and matches the current macOS appearance, so a machine set
# up in dark mode doesn't start light.
echo
if ! compgen -G "$THEMES_DIR/*.json" >/dev/null; then
  echo "Warning: no theme files in $THEMES_DIR — run 'stow --no-folding pi' from"
  echo "the repo root first, then re-run this script, or pi will fall back to its"
  echo "built-in theme because \"active\" resolves to nothing."
elif [ -e "$ACTIVE_FILE" ]; then
  echo "Theme: $ACTIVE_FILE already exists — left as-is."
elif [ -x "$THEME_BIN" ]; then
  "$THEME_BIN" seed
  # seed warns but doesn't fail when the pi palette isn't in THEMES_DIR — say
  # so here, since settings.json above already points at the empty slot.
  [ -e "$ACTIVE_FILE" ] \
    || echo "Warning: 'theme seed' did not create $ACTIVE_FILE — is the pi palette stowed?"
else
  echo "Warning: $THEME_BIN not found — active.json not seeded."
  echo "Run 'theme seed' after stowing the zsh package."
fi

echo
echo "Set OPENROUTER_API_KEY in ~/.zshenv (README → \"OpenRouter\"), then run \`pi\`."
echo "Switch themes with \`theme dark|light|toggle\`."
