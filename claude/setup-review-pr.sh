#!/bin/bash
# One-time setup: activate the review-pr skill for this machine. Run after
# `stow claude`.
#
# The repo tracks SKILL.generic.md (provider-neutral), but SKILL.md itself is
# NOT tracked or stowed — this script creates it as a machine-local symlink to
# the tracked variant, so a later `stow -R claude` / `git pull` can never
# overwrite a per-machine choice. On a machine that needs project-specific
# tweaks, drop a private SKILL.*.md next to it and point SKILL.md there instead.
#
# Usage:
#   setup-review-pr.sh

set -euo pipefail

DIR="$HOME/.claude/skills/review-pr"
SOURCE_FILE="$DIR/SKILL.generic.md"

# Don't point SKILL.md at a variant that isn't stowed yet — run `stow claude` first.
if [ ! -e "$SOURCE_FILE" ]; then
  echo "Error: variant file not found at $SOURCE_FILE"
  echo "Run 'stow --no-folding claude' from the repo root first, then re-run this script."
  exit 1
fi

# Relative symlink (not absolute) so it resolves the same on any machine.
# -f replaces an existing link atomically, including a dangling one.
ln -sfn "SKILL.generic.md" "$DIR/SKILL.md"

echo "review-pr -> generic"
