#!/bin/bash
# One-time setup: point ~/.claude/settings.json at the "active" theme slot used
# by the unified `theme` switcher (see README → "Unified theme switching").
# Run after `stow claude`.
#
# Indirection: settings.json pins a FIXED slug, "custom:active", and the
# `theme dark|light` command swaps what ~/.claude/themes/active.json *contains*.
# Claude hot-reloads theme files, so this gives a live dark/light switch with no
# restart. This script just sets the preference and seeds active.json from a
# sensible default. settings.json is stowed, so on a stowed machine the
# preference is usually set already — seeding active.json is the real work.

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
THEME="custom:active"
THEMES_DIR="$HOME/.claude/themes"
ACTIVE_FILE="$THEMES_DIR/active.json"
# Repo-relative so it works before `stow zsh` puts `theme` on PATH.
THEME_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/zsh/.local/bin/theme"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

# Don't point settings.json at themes that aren't stowed yet — run `stow claude` first.
if ! compgen -G "$THEMES_DIR/*.json" >/dev/null; then
  echo "Error: no theme files found in $THEMES_DIR"
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi

# Seed active.json (a real file, not stowed) so "custom:active" resolves.
# `theme seed` owns the palette choice — the pair lives only in that script's
# LIGHT/DARK arrays — and matches the current macOS appearance.
if [ ! -e "$ACTIVE_FILE" ]; then
  if [ -x "$THEME_BIN" ]; then
    "$THEME_BIN" seed
    # seed warns but doesn't fail when the pair's palette isn't in THEMES_DIR
    # (the compgen guard above only proves *some* JSON exists) — don't pin
    # settings at a slot that never materialized.
    if [ ! -e "$ACTIVE_FILE" ]; then
      echo "Error: 'theme seed' did not create $ACTIVE_FILE — is the pair's palette stowed?"
      echo "Leaving settings.json untouched; fix the stow and re-run."
      exit 1
    fi
  else
    echo "Warning: $THEME_BIN not found — active.json not seeded."
    echo "Run 'theme seed' after stowing the zsh package, or Claude will fall"
    echo "back to its built-in theme because 'custom:active' resolves to nothing."
  fi
fi

if [ ! -f "$SETTINGS" ]; then
  echo "Error: no settings.json found at $SETTINGS."
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi

# settings.json is stowed (a symlink into the repo): write through the link.
# `mv tmp` onto the link path would replace the LINK with a plain file,
# silently de-adopting the stowed copy. Needs macOS >= 12.3's readlink -f
# (stock older macOS lacks the flag).
SETTINGS="$(readlink -f "$SETTINGS")"

current=$(jq -r '.theme // empty' "$SETTINGS")

if [ "$current" = "$THEME" ]; then
  echo "Theme already set to $THEME — no change."
else
  [ -n "$current" ] && echo "Changing theme from '$current' to '$THEME'..." \
                    || echo "Setting theme to '$THEME'..."
  tmp="$(mktemp "${SETTINGS}.XXXXXX")"
  jq --arg t "$THEME" '.theme = $t' "$SETTINGS" > "$tmp" \
    && mv "$tmp" "$SETTINGS" || { rm -f "$tmp"; exit 1; }
  echo "Done. Use 'theme dark|light|toggle' to switch."
fi
