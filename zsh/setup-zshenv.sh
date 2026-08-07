#!/bin/bash
# One-time setup: seed this machine's ~/.zshenv with an empty
# OPENROUTER_API_KEY so opencode/pi have somewhere to read a key from.
#
# ~/.zshenv is deliberately NOT stowed — it holds a live credential once you
# fill it in, and a stowed symlink would put that straight into this repo.
# See README -> "OpenRouter" for why ~/.zshenv (not the stowed zsh config) is
# the right file.
#
# Idempotent: if ~/.zshenv already exists, it's left untouched (it may
# already hold a real key) — this only creates it when missing.
#
# Usage:
#   bash ~/src/dotfiles/zsh/setup-zshenv.sh

set -euo pipefail

ZSHENV="$HOME/.zshenv"

if [ -e "$ZSHENV" ]; then
  echo "$ZSHENV already exists — left as-is."
else
  printf 'export OPENROUTER_API_KEY=""\n' >"$ZSHENV"
  chmod 600 "$ZSHENV"
  echo "Created $ZSHENV — fill in OPENROUTER_API_KEY (README -> \"OpenRouter\")."
fi
